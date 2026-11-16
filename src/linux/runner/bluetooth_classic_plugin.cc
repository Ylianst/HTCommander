// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Native Linux Bluetooth Classic (RFCOMM) plugin implementation. See the
// header for the channel contract. Mirrors the behavior of the Windows/macOS/
// Android native bridges.

#include "bluetooth_classic_plugin.h"

#include <gio/gio.h>

#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
#include <bluetooth/sdp.h>
#include <bluetooth/sdp_lib.h>

#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <vector>

// ---------------------------------------------------------------------------
// Channel names (must match the Dart BluetoothClassicMacOS wrapper).
// ---------------------------------------------------------------------------
#define BT_METHOD_CHANNEL "com.htcommander/bluetooth_classic"
#define BT_DATA_CHANNEL "com.htcommander/bluetooth_classic_data"
#define BT_AUDIO_CHANNEL "com.htcommander/bluetooth_classic_audio"

// Vendor "BS AOC" SDP service UUID that uniquely identifies a compatible
// radio. BlueZ exposes a device's cached SDP service UUIDs via the "UUIDs"
// property of org.bluez.Device1; a device is treated as a radio when this
// service is present. Matching by UUID is stable across rebrands / name
// changes, unlike the previous name-substring matching. Generic services
// (SPP 0x1101, Generic Audio 0x1203) are intentionally not used here.
static const char* kRadioServiceUuid = "39144315-32fa-40db-85ed-fbfeba2d86e6";

// ---------------------------------------------------------------------------
// Plugin + connection state
// ---------------------------------------------------------------------------
typedef struct _BtConnection BtConnection;

struct BtPreparedJob {
  gint64 id;
  std::vector<guint8> data;
  std::vector<gint32> lengths;
  std::vector<gint32> samples;
  gint64 lead_ms;
  FlMethodCall* call;
  gboolean cancelled = FALSE;  // guarded by connection's tx_mutex
  gboolean success = FALSE;
  gint64 samples_sent = 0;
  gint64 writes = 0;  // complete audio batches (not marker or partial sends)
  gint64 elapsed_ms = 0;
  gint64 max_write_ms = 0;
  gint64 max_gap_ms = 0;
  gint64 max_behind_ms = 0;
};

typedef struct {
  FlMethodChannel* method_channel;
  FlEventChannel* data_channel;
  FlEventChannel* audio_channel;
  gboolean data_listening;   // touched only on the platform (main) thread
  gboolean audio_listening;  // touched only on the platform (main) thread
  GMutex mutex;              // guards `connections` + `audio_connections`
  GHashTable* connections;        // char* address -> BtConnection* (control)
  GHashTable* audio_connections;  // char* address -> BtConnection* (audio)
  gboolean stopping;              // guarded by mutex
  gint refcount;
} BtPlugin;

struct _BtConnection {
  BtPlugin* plugin;
  gchar* address;      // normalized "AA:BB:CC:DD:EE:FF"
  int fd;              // RFCOMM socket
  gboolean is_audio;   // true for the audio (BS AOC) channel
  gint running;        // accessed via g_atomic_int_*
  gint refcount;
  GMutex tx_mutex;
  GCond tx_cond;
  BtPreparedJob* job;
  gboolean streaming;
};

// Single plugin instance for the app lifetime.
static BtPlugin* g_bt_plugin = NULL;

static BtPlugin* bt_plugin_ref(BtPlugin* p) {
  g_atomic_int_inc(&p->refcount);
  return p;
}

static void bt_plugin_unref(BtPlugin* p) {
  if (g_atomic_int_dec_and_test(&p->refcount)) {
    g_hash_table_unref(p->connections);
    g_hash_table_unref(p->audio_connections);
    g_mutex_clear(&p->mutex);
    g_free(p);
  }
}

// Select the connection map for the control or audio channel.
static GHashTable* bt_map_for(BtPlugin* p, gboolean is_audio) {
  return is_audio ? p->audio_connections : p->connections;
}

// ---------------------------------------------------------------------------
// BtConnection refcounting
// ---------------------------------------------------------------------------
static BtConnection* bt_conn_ref(BtConnection* c) {
  g_atomic_int_inc(&c->refcount);
  return c;
}

static void bt_conn_unref(BtConnection* c) {
  if (g_atomic_int_dec_and_test(&c->refcount)) {
    if (c->fd >= 0) close(c->fd);
    g_cond_clear(&c->tx_cond);
    g_mutex_clear(&c->tx_mutex);
    g_free(c->address);
    bt_plugin_unref(c->plugin);
    g_free(c);
  }
}

static void bt_conn_stop(BtConnection* c) {
  g_mutex_lock(&c->tx_mutex);
  g_atomic_int_set(&c->running, 0);
  g_cond_broadcast(&c->tx_cond);
  g_mutex_unlock(&c->tx_mutex);
  shutdown(c->fd, SHUT_RDWR);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static gchar* bt_normalize_addr(const char* s) {
  gchar* up = g_ascii_strup(s, -1);
  for (char* p = up; *p; ++p) {
    if (*p == '-') *p = ':';
  }
  return up;  // caller frees
}

// Returns the radio service UUIDs a device exposes, matched against the known
// vendor identifier, as a newly-allocated FlValue string list (caller owns).
// The list is empty when the device is not a compatible radio. `uuids_variant`
// is the "UUIDs" property of org.bluez.Device1 (type "as"), or NULL.
static FlValue* bt_radio_service_uuids(GVariant* uuids_variant) {
  FlValue* matched = fl_value_new_list();
  if (!uuids_variant) return matched;
  GVariantIter it;
  g_variant_iter_init(&it, uuids_variant);
  const gchar* u = NULL;
  while (g_variant_iter_next(&it, "&s", &u)) {
    if (u && g_ascii_strcasecmp(u, kRadioServiceUuid) == 0) {
      fl_value_append_take(matched, fl_value_new_string(kRadioServiceUuid));
    }
  }
  return matched;
}

static gboolean bt_write_all(int fd, const guint8* data, gsize len) {
  gsize off = 0;
  while (off < len) {
    ssize_t w = write(fd, data + off, len - off);
    if (w <= 0) {
      if (w < 0 && errno == EINTR) continue;
      return FALSE;
    }
    off += (gsize)w;
  }
  return TRUE;
}

// Resolve the RFCOMM channel that advertises the given SDP service UUID.
// Returns the channel number (>=1) or -1 if it could not be determined.
static int bt_find_channel_for_uuid(const bdaddr_t* target, uuid_t* svc_uuid) {
  int channel = -1;
  bdaddr_t any;
  memset(&any, 0, sizeof(any));  // BDADDR_ANY
  sdp_session_t* session = sdp_connect(&any, target, SDP_RETRY_IF_BUSY);
  if (!session) return -1;

  sdp_list_t* search_list = sdp_list_append(NULL, svc_uuid);
  uint32_t range = 0x0000ffff;
  sdp_list_t* attrid_list = sdp_list_append(NULL, &range);
  sdp_list_t* response_list = NULL;

  if (sdp_service_search_attr_req(session, search_list, SDP_ATTR_REQ_RANGE,
                                  attrid_list, &response_list) == 0) {
    for (sdp_list_t* r = response_list; r; r = r->next) {
      sdp_record_t* rec = (sdp_record_t*)r->data;
      sdp_list_t* proto_list = NULL;
      if (sdp_get_access_protos(rec, &proto_list) == 0) {
        int ch = sdp_get_proto_port(proto_list, RFCOMM_UUID);
        if (ch > 0) channel = ch;
        for (sdp_list_t* p = proto_list; p; p = p->next) {
          sdp_list_free((sdp_list_t*)p->data, NULL);
        }
        sdp_list_free(proto_list, NULL);
      }
      if (channel > 0) break;
    }
  }

  for (sdp_list_t* r = response_list; r; r = r->next) {
    sdp_record_free((sdp_record_t*)r->data);
  }
  sdp_list_free(response_list, NULL);
  sdp_list_free(search_list, NULL);
  sdp_list_free(attrid_list, NULL);
  sdp_close(session);
  return channel;
}

// Control channel: Serial Port Profile (0x1101).
static int bt_find_control_channel(const bdaddr_t* target) {
  uuid_t u;
  sdp_uuid16_create(&u, SERIAL_PORT_SVCLASS_ID);
  return bt_find_channel_for_uuid(target, &u);
}

// Audio channel: the vendor "BS AOC" 128-bit service carries the SBC audio
// stream on these radios. The advertised Generic Audio service (0x1203) is a
// fallback for models that do not expose BS AOC. See docs/radio-bluetooth.md.
static int bt_find_audio_channel(const bdaddr_t* target) {
  static const uint8_t kBsAoc[16] = {0x39, 0x14, 0x43, 0x15, 0x32, 0xFA,
                                     0x40, 0xDB, 0x85, 0xED, 0xFB, 0xFE,
                                     0xBA, 0x2D, 0x86, 0xE6};
  uuid_t u;
  sdp_uuid128_create(&u, kBsAoc);
  int channel = bt_find_channel_for_uuid(target, &u);
  if (channel < 1) {
    uuid_t generic;
    sdp_uuid16_create(&generic, 0x1203);
    channel = bt_find_channel_for_uuid(target, &generic);
  }
  return channel;
}

// Open and connect an RFCOMM socket. Returns fd or -1.
static int bt_rfcomm_connect(const char* address, int channel) {
  int s = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
  if (s < 0) {
    g_warning("[BT-Classic] socket() failed: %s", g_strerror(errno));
    return -1;
  }

  struct sockaddr_rc addr;
  memset(&addr, 0, sizeof(addr));
  addr.rc_family = AF_BLUETOOTH;
  addr.rc_channel = (uint8_t)channel;
  str2ba(address, &addr.rc_bdaddr);

  if (connect(s, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
    g_warning("[BT-Classic] connect(%s, ch=%d) failed: %s", address, channel,
              g_strerror(errno));
    close(s);
    return -1;
  }
  g_message("[BT-Classic] RFCOMM connected to %s on channel %d", address,
            channel);
  return s;
}

// ---------------------------------------------------------------------------
// BlueZ D-Bus enumeration
// ---------------------------------------------------------------------------
static FlValue* bt_enumerate_devices(gboolean compatible_only) {
  FlValue* list = fl_value_new_list();

  GError* error = NULL;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
  if (!bus) {
    g_clear_error(&error);
    return list;
  }

  GVariant* reply = g_dbus_connection_call_sync(
      bus, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
      "GetManagedObjects", NULL, G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
      G_DBUS_CALL_FLAGS_NONE, 5000, NULL, &error);
  if (!reply) {
    g_clear_error(&error);
    g_object_unref(bus);
    return list;
  }

  GVariantIter* obj_iter = NULL;
  g_variant_get(reply, "(a{oa{sa{sv}}})", &obj_iter);
  const gchar* path = NULL;
  GVariant* ifaces = NULL;
  while (g_variant_iter_loop(obj_iter, "{&o@a{sa{sv}}}", &path, &ifaces)) {
    GVariant* dev =
        g_variant_lookup_value(ifaces, "org.bluez.Device1",
                               G_VARIANT_TYPE("a{sv}"));
    if (!dev) continue;

    gchar* addr = NULL;
    gchar* name = NULL;
    gchar* alias = NULL;
    gboolean paired = FALSE;
    gboolean connected = FALSE;
    GVariant* v = NULL;

    if ((v = g_variant_lookup_value(dev, "Address", G_VARIANT_TYPE_STRING))) {
      addr = g_variant_dup_string(v, NULL);
      g_variant_unref(v);
    }
    if ((v = g_variant_lookup_value(dev, "Name", G_VARIANT_TYPE_STRING))) {
      name = g_variant_dup_string(v, NULL);
      g_variant_unref(v);
    }
    if ((v = g_variant_lookup_value(dev, "Alias", G_VARIANT_TYPE_STRING))) {
      alias = g_variant_dup_string(v, NULL);
      g_variant_unref(v);
    }
    if ((v = g_variant_lookup_value(dev, "Paired", G_VARIANT_TYPE_BOOLEAN))) {
      paired = g_variant_get_boolean(v);
      g_variant_unref(v);
    }
    if ((v = g_variant_lookup_value(dev, "Connected", G_VARIANT_TYPE_BOOLEAN))) {
      connected = g_variant_get_boolean(v);
      g_variant_unref(v);
    }

    // Identify radios by their unique vendor SDP service UUID rather than by
    // name. BlueZ caches the paired device's service UUIDs in this property.
    FlValue* radio_uuids = NULL;
    if ((v = g_variant_lookup_value(dev, "UUIDs", G_VARIANT_TYPE_STRING_ARRAY))) {
      radio_uuids = bt_radio_service_uuids(v);
      g_variant_unref(v);
    } else {
      radio_uuids = fl_value_new_list();
    }
    gboolean is_radio = fl_value_get_length(radio_uuids) > 0;

    const char* disp = (name && *name) ? name : (alias ? alias : "");
    if ((!compatible_only || is_radio) && addr && *addr && *disp) {
      gchar* norm = bt_normalize_addr(addr);
      FlValue* m = fl_value_new_map();
      fl_value_set_string_take(m, "name", fl_value_new_string(disp));
      fl_value_set_string_take(m, "address", fl_value_new_string(norm));
      fl_value_set_string_take(m, "isPaired", fl_value_new_bool(paired));
      fl_value_set_string_take(m, "isConnected", fl_value_new_bool(connected));
      fl_value_set_string_take(m, "serviceUuids", radio_uuids);
      fl_value_append_take(list, m);
      g_free(norm);
    } else {
      fl_value_unref(radio_uuids);
    }

    g_free(addr);
    g_free(name);
    g_free(alias);
    g_variant_unref(dev);
  }

  if (obj_iter) g_variant_iter_free(obj_iter);
  g_variant_unref(reply);
  g_object_unref(bus);
  return list;
}

static FlValue* bt_enumerate_device_names(void) {
  g_autoptr(FlValue) devices = bt_enumerate_devices(FALSE);
  FlValue* names = fl_value_new_list();
  size_t n = fl_value_get_length(devices);
  for (size_t i = 0; i < n; ++i) {
    FlValue* m = fl_value_get_list_value(devices, i);
    FlValue* nm = fl_value_lookup_string(m, "name");
    if (nm && fl_value_get_type(nm) == FL_VALUE_TYPE_STRING) {
      fl_value_append_take(names, fl_value_new_string(fl_value_get_string(nm)));
    }
  }
  return names;
}

static gboolean bt_any_adapter_powered(void) {
  GError* error = NULL;
  GDBusConnection* bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
  if (!bus) {
    g_clear_error(&error);
    return FALSE;
  }

  GVariant* reply = g_dbus_connection_call_sync(
      bus, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
      "GetManagedObjects", NULL, G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
      G_DBUS_CALL_FLAGS_NONE, 5000, NULL, &error);
  if (!reply) {
    g_clear_error(&error);
    g_object_unref(bus);
    return FALSE;
  }

  gboolean powered = FALSE;
  GVariantIter* obj_iter = NULL;
  g_variant_get(reply, "(a{oa{sa{sv}}})", &obj_iter);
  const gchar* path = NULL;
  GVariant* ifaces = NULL;
  while (!powered &&
         g_variant_iter_loop(obj_iter, "{&o@a{sa{sv}}}", &path, &ifaces)) {
    GVariant* adapter =
        g_variant_lookup_value(ifaces, "org.bluez.Adapter1",
                               G_VARIANT_TYPE("a{sv}"));
    if (!adapter) continue;
    GVariant* v =
        g_variant_lookup_value(adapter, "Powered", G_VARIANT_TYPE_BOOLEAN);
    if (v) {
      powered = g_variant_get_boolean(v);
      g_variant_unref(v);
    }
    g_variant_unref(adapter);
  }

  if (obj_iter) g_variant_iter_free(obj_iter);
  g_variant_unref(reply);
  g_object_unref(bus);
  return powered;
}

// ---------------------------------------------------------------------------
// Event dispatch (marshaled to the platform thread via g_idle_add)
// ---------------------------------------------------------------------------
typedef struct {
  gboolean is_audio;
  gchar* type;
  gchar* address;
  guint8* data;
  gsize data_len;
} BtEventMsg;

static gboolean bt_emit_event_idle(gpointer user_data) {
  BtEventMsg* m = (BtEventMsg*)user_data;
  BtPlugin* p = g_bt_plugin;
  if (p) {
    FlEventChannel* ch = m->is_audio ? p->audio_channel : p->data_channel;
    gboolean listening = m->is_audio ? p->audio_listening : p->data_listening;
    if (ch && listening) {
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "event", fl_value_new_string(m->type));
      fl_value_set_string_take(map, "address",
                               fl_value_new_string(m->address));
      if (m->data) {
        fl_value_set_string_take(
            map, "data", fl_value_new_uint8_list(m->data, m->data_len));
      }
      fl_event_channel_send(ch, map, NULL, NULL);
    }
  }
  g_free(m->type);
  g_free(m->address);
  g_free(m->data);
  g_free(m);
  return G_SOURCE_REMOVE;
}

static void bt_emit_event(gboolean is_audio, const char* type,
                          const char* address, const guint8* data, gsize len) {
  BtEventMsg* m = g_new0(BtEventMsg, 1);
  m->is_audio = is_audio;
  m->type = g_strdup(type);
  m->address = g_strdup(address);
  if (data && len) {
    m->data = (guint8*)g_malloc(len);
    memcpy(m->data, data, len);
    m->data_len = len;
  }
  g_idle_add(bt_emit_event_idle, m);
}

// ---------------------------------------------------------------------------
// Method-call response marshaling (used by the async connect worker)
// ---------------------------------------------------------------------------
typedef struct {
  FlMethodCall* call;
  gboolean result;
} BtRespMsg;

static gboolean bt_respond_bool_idle(gpointer user_data) {
  BtRespMsg* r = (BtRespMsg*)user_data;
  g_autoptr(FlValue) v = fl_value_new_bool(r->result);
  fl_method_call_respond_success(r->call, v, NULL);
  g_object_unref(r->call);
  g_free(r);
  return G_SOURCE_REMOVE;
}

static void bt_respond_bool_async(FlMethodCall* call, gboolean result) {
  BtRespMsg* r = g_new0(BtRespMsg, 1);
  r->call = FL_METHOD_CALL(g_object_ref(call));
  r->result = result;
  g_idle_add(bt_respond_bool_idle, r);
}

// No Flutter API (including result construction/unref) is called by TX workers.
static gboolean bt_prepared_result_idle(gpointer user_data) {
  BtPreparedJob* job = static_cast<BtPreparedJob*>(user_data);
  if (!job->success) {
    fl_method_call_respond_error(job->call, "SEND_FAILED",
                                "Audio connection closed or write timed out",
                                NULL, NULL);
  } else {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "status",
        fl_value_new_string(job->cancelled ? "cancelled" : "submitted"));
    fl_value_set_string_take(result, "samplesSent", fl_value_new_int(job->samples_sent));
    fl_value_set_string_take(result, "writes", fl_value_new_int(job->writes));
    fl_value_set_string_take(result, "elapsedMs", fl_value_new_int(job->elapsed_ms));
    fl_value_set_string_take(result, "maxWriteMs", fl_value_new_int(job->max_write_ms));
    fl_value_set_string_take(result, "maxGapMs", fl_value_new_int(job->max_gap_ms));
    fl_value_set_string_take(result, "maxBehindMs", fl_value_new_int(job->max_behind_ms));
    fl_method_call_respond_success(job->call, result, NULL);
  }
  g_object_unref(job->call);
  delete job;
  return G_SOURCE_REMOVE;
}

enum class BtWriteResult { complete, cancelled, failed };

// Keep RX blocking: MSG_DONTWAIT applies only to this send. Cancellation skips
// an untouched batch, but finishes any partial frame before the end marker.
// A stalled partial batch/marker aborts the connection after five seconds.
static BtWriteResult bt_prepared_write(BtConnection* conn, const guint8* data,
                                       gsize len, gboolean marker) {
  gsize offset = 0;
  gint64 deadline = g_get_monotonic_time() + 5 * G_USEC_PER_SEC;
  while (offset < len) {
    g_mutex_lock(&conn->tx_mutex);
    gboolean cancelled = conn->job->cancelled;
    gboolean running = g_atomic_int_get(&conn->running);
    g_mutex_unlock(&conn->tx_mutex);
    if (!running) return BtWriteResult::failed;
    if (!marker && offset == 0 && cancelled) return BtWriteResult::cancelled;
    if (g_get_monotonic_time() >= deadline) return BtWriteResult::failed;
    ssize_t n = send(conn->fd, data + offset, len - offset,
                     MSG_DONTWAIT | MSG_NOSIGNAL);
    if (n > 0) {
      offset += static_cast<gsize>(n);
    } else if (n < 0 && errno == EINTR) {
      continue;
    } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd fd = {conn->fd, POLLOUT, 0};
      int rc = poll(&fd, 1, 50);
      if (rc < 0 && errno == EINTR) continue;
      if (rc < 0 || (rc > 0 && (fd.revents & (POLLERR | POLLHUP | POLLNVAL))))
        return BtWriteResult::failed;
    } else {
      return BtWriteResult::failed;
    }
  }
  return BtWriteResult::complete;
}

static gpointer bt_prepared_thread(gpointer user_data) {
  BtConnection* conn = static_cast<BtConnection*>(user_data);
  static const guint8 marker[] = {0x7e, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0x7e};
  for (;;) {
    g_mutex_lock(&conn->tx_mutex);
    while (g_atomic_int_get(&conn->running) && !conn->job)
      g_cond_wait(&conn->tx_cond, &conn->tx_mutex);
    BtPreparedJob* job = conn->job;
    gboolean running = g_atomic_int_get(&conn->running);
    g_mutex_unlock(&conn->tx_mutex);
    if (!job) break;

    gint64 start = g_get_monotonic_time();
    gint64 last_end = start;
    gint64 max_write = 0, max_gap = 0, max_behind = 0;
    gsize offset = 0;
    gboolean ok = running;
    for (gsize i = 0; ok && i < job->lengths.size(); ++i) {
      gint64 due = start + std::max<gint64>(0,
          (job->samples_sent + job->samples[i]) * G_USEC_PER_SEC / 32000 -
          job->lead_ms * 1000);
      g_mutex_lock(&conn->tx_mutex);
      while (g_atomic_int_get(&conn->running) && !job->cancelled &&
             g_get_monotonic_time() < due)
        g_cond_wait_until(&conn->tx_cond, &conn->tx_mutex, due);
      gboolean stop = job->cancelled || !g_atomic_int_get(&conn->running);
      g_mutex_unlock(&conn->tx_mutex);
      if (stop) break;
      gint64 before = g_get_monotonic_time();
      BtWriteResult sent = bt_prepared_write(conn, job->data.data() + offset,
                                             job->lengths[i], FALSE);
      if (sent == BtWriteResult::cancelled) break;
      if (sent == BtWriteResult::failed) { ok = FALSE; break; }
      gint64 end = g_get_monotonic_time();
      max_write = std::max(max_write, end - before);
      max_gap = std::max(max_gap, before - last_end);
      max_behind = std::max(max_behind, before - due);
      last_end = end;
      offset += job->lengths[i];
      job->samples_sent += job->samples[i];
    }
    if (ok) {
      gint64 before = g_get_monotonic_time();
      ok = bt_prepared_write(conn, marker, sizeof(marker), TRUE) ==
           BtWriteResult::complete;
      if (ok) {
        max_write = std::max(max_write, g_get_monotonic_time() - before);
        max_gap = std::max(max_gap, before - last_end);
        job->writes++;
      }
    }
    job->elapsed_ms = (g_get_monotonic_time() - start) / 1000;
    job->max_write_ms = max_write / 1000;
    job->max_gap_ms = max_gap / 1000;
    job->max_behind_ms = max_behind / 1000;
    g_mutex_lock(&conn->tx_mutex);
    job->success = ok && g_atomic_int_get(&conn->running);
    if (!job->success) {
      g_atomic_int_set(&conn->running, 0);
      shutdown(conn->fd, SHUT_RDWR);
    }
    conn->job = NULL;
    g_mutex_unlock(&conn->tx_mutex);
    g_idle_add(bt_prepared_result_idle, job);
    if (!ok) {
      // TX errors also retire the map entry; RX uses the same identity check
      // so only one worker emits the disconnected event.
      BtPlugin* p = conn->plugin;
      g_mutex_lock(&p->mutex);
      GHashTable* map = bt_map_for(p, TRUE);
      if (g_hash_table_lookup(map, conn->address) == conn) {
        g_hash_table_remove(map, conn->address);
        bt_emit_event(TRUE, "disconnected", conn->address, NULL, 0);
      }
      g_mutex_unlock(&p->mutex);
    }
  }
  bt_conn_unref(conn);
  return NULL;
}

// ---------------------------------------------------------------------------
// Read loop — runs on a dedicated background thread per connection.
// ---------------------------------------------------------------------------
static gpointer bt_read_thread(gpointer user_data) {
  BtConnection* conn = (BtConnection*)user_data;
  gboolean is_audio = conn->is_audio;
  guint8 buf[4096];

  while (g_atomic_int_get(&conn->running)) {
    ssize_t n = read(conn->fd, buf, sizeof(buf));
    if (n > 0) {
      bt_emit_event(is_audio, "data", conn->address, buf, (gsize)n);
    } else if (n == 0) {
      break;  // Remote closed the connection.
    } else {
      if (errno == EINTR) continue;
      break;  // Socket error / shutdown.
    }
  }

  // If running was still 1, this was an unexpected close: emit disconnected and
  // drop it from the connection map. If it was already 0, an explicit
  // disconnect handled the event and the map removal already.
  if (g_atomic_int_compare_and_exchange(&conn->running, 1, 0)) {
    bt_conn_stop(conn);
    BtPlugin* p = conn->plugin;
    g_mutex_lock(&p->mutex);
    GHashTable* map = bt_map_for(p, is_audio);
    BtConnection* cur =
        (BtConnection*)g_hash_table_lookup(map, conn->address);
    if (cur == conn) {
      g_hash_table_remove(map, conn->address);
      bt_emit_event(is_audio, "disconnected", conn->address, NULL, 0);
    }
    g_mutex_unlock(&p->mutex);
  }

  bt_conn_unref(conn);  // Release the read thread's reference.
  return NULL;
}

// ---------------------------------------------------------------------------
// Async connect worker
// ---------------------------------------------------------------------------
typedef struct {
  gchar* address;
  FlMethodCall* call;
  gboolean is_audio;
  BtPlugin* plugin;
} BtConnectTask;

static gpointer bt_connect_thread(gpointer user_data) {
  BtConnectTask* t = (BtConnectTask*)user_data;
  BtPlugin* p = t->plugin;

  bdaddr_t target;
  str2ba(t->address, &target);

  int channel;
  if (t->is_audio) {
    channel = bt_find_audio_channel(&target);
    g_message("[BT-Classic] SDP audio channel for %s = %d", t->address,
              channel);
  } else {
    channel = bt_find_control_channel(&target);
    g_message("[BT-Classic] SDP control channel for %s = %d", t->address,
              channel);
    if (channel < 1) channel = 1;  // Fallback: SPP is commonly on channel 1.
  }

  int fd = (channel >= 1) ? bt_rfcomm_connect(t->address, channel) : -1;
  gboolean ok = FALSE;

  if (fd >= 0) {
    BtConnection* conn = g_new0(BtConnection, 1);
    conn->plugin = bt_plugin_ref(p);
    conn->address = g_strdup(t->address);
    conn->fd = fd;
    conn->is_audio = t->is_audio;
    conn->refcount = 1;  // Owned by the hash table.
    g_mutex_init(&conn->tx_mutex);
    g_cond_init(&conn->tx_cond);
    g_atomic_int_set(&conn->running, 1);

    g_mutex_lock(&p->mutex);
    BtConnection* old = static_cast<BtConnection*>(
        g_hash_table_lookup(bt_map_for(p, t->is_audio), conn->address));
    if (old) bt_conn_stop(old);
    if (p->stopping) {
      g_mutex_unlock(&p->mutex);
      bt_conn_unref(conn);
      bt_respond_bool_async(t->call, FALSE);
      g_object_unref(t->call);
      g_free(t->address);
      bt_plugin_unref(t->plugin);
      g_free(t);
      return NULL;
    }
    // Hold thread references before publishing the connection.
    bt_conn_ref(conn);
    if (t->is_audio) bt_conn_ref(conn);
    bt_conn_ref(conn);  // Local setup reference, even if RX exits immediately.
    g_hash_table_replace(bt_map_for(p, t->is_audio), g_strdup(conn->address),
                         conn);
    g_mutex_unlock(&p->mutex);

    GThread* th = g_thread_new("bt-read", bt_read_thread, conn);
    g_thread_unref(th);
    if (t->is_audio) {
      th = g_thread_new("bt-audio-tx", bt_prepared_thread, conn);
      g_thread_unref(th);
    }

    bt_emit_event(t->is_audio, "connected", conn->address, NULL, 0);
    bt_conn_unref(conn);
    ok = TRUE;
  }

  bt_respond_bool_async(t->call, ok);
  g_object_unref(t->call);
  g_free(t->address);
  bt_plugin_unref(t->plugin);
  g_free(t);
  return NULL;
}

// ---------------------------------------------------------------------------
// Method channel handler (runs on the platform thread)
// ---------------------------------------------------------------------------
static void bt_respond_bool_sync(FlMethodCall* call, gboolean v) {
  g_autoptr(FlValue) val = fl_value_new_bool(v);
  fl_method_call_respond_success(call, val, NULL);
}

// Shared connect handler for both the control and audio RFCOMM channels.
static void bt_handle_connect(FlMethodCall* call, FlValue* args,
                              gboolean is_audio) {
  BtPlugin* p = g_bt_plugin;
  FlValue* a = args ? fl_value_lookup_string(args, "address") : NULL;
  if (!a || fl_value_get_type(a) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "INVALID_ARGS", "Missing address", NULL,
                                 NULL);
    return;
  }
  gchar* addr = bt_normalize_addr(fl_value_get_string(a));
  g_mutex_lock(&p->mutex);
  gboolean exists = g_hash_table_contains(bt_map_for(p, is_audio), addr);
  g_mutex_unlock(&p->mutex);
  if (exists) {
    bt_respond_bool_sync(call, TRUE);
    g_free(addr);
    return;
  }
  BtConnectTask* t = g_new0(BtConnectTask, 1);
  t->address = addr;  // Ownership transferred to the task.
  t->call = FL_METHOD_CALL(g_object_ref(call));
  t->is_audio = is_audio;
  t->plugin = bt_plugin_ref(p);
  GThread* th = g_thread_new("bt-connect", bt_connect_thread, t);
  g_thread_unref(th);
}

// Shared disconnect handler for both channels.
static void bt_handle_disconnect(FlMethodCall* call, FlValue* args,
                                 gboolean is_audio) {
  BtPlugin* p = g_bt_plugin;
  FlValue* a = args ? fl_value_lookup_string(args, "address") : NULL;
  if (!a || fl_value_get_type(a) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "INVALID_ARGS", "Missing address", NULL,
                                 NULL);
    return;
  }
  gchar* addr = bt_normalize_addr(fl_value_get_string(a));
  g_mutex_lock(&p->mutex);
  GHashTable* map = bt_map_for(p, is_audio);
  BtConnection* conn = (BtConnection*)g_hash_table_lookup(map, addr);
  if (conn) {
    bt_conn_ref(conn);  // Keep alive while we tear down.
    g_hash_table_remove(map, addr);
  }
  g_mutex_unlock(&p->mutex);
  if (conn) {
    bt_conn_stop(conn);
    bt_emit_event(is_audio, "disconnected", addr, NULL, 0);
    bt_conn_unref(conn);
  }
  g_free(addr);
  bt_respond_bool_sync(call, TRUE);
}

// Shared send handler for both channels.
static void bt_handle_send(FlMethodCall* call, FlValue* args,
                           gboolean is_audio) {
  BtPlugin* p = g_bt_plugin;
  FlValue* a = args ? fl_value_lookup_string(args, "address") : NULL;
  FlValue* d = args ? fl_value_lookup_string(args, "data") : NULL;
  if (!a || fl_value_get_type(a) != FL_VALUE_TYPE_STRING || !d ||
      fl_value_get_type(d) != FL_VALUE_TYPE_UINT8_LIST) {
    fl_method_call_respond_error(call, "INVALID_ARGS",
                                 "Missing address or data", NULL, NULL);
    return;
  }
  gchar* addr = bt_normalize_addr(fl_value_get_string(a));
  const uint8_t* bytes = fl_value_get_uint8_list(d);
  gsize len = fl_value_get_length(d);

  g_mutex_lock(&p->mutex);
  BtConnection* conn =
      (BtConnection*)g_hash_table_lookup(bt_map_for(p, is_audio), addr);
  if (conn) bt_conn_ref(conn);
  g_mutex_unlock(&p->mutex);
  g_free(addr);

  gboolean ok = FALSE;
  gboolean busy = FALSE;
  if (conn && is_audio) {
    g_mutex_lock(&conn->tx_mutex);
    busy = conn->job != NULL;
    if (!busy) conn->streaming = TRUE;
    g_mutex_unlock(&conn->tx_mutex);
  }
  if (conn && !busy && g_atomic_int_get(&conn->running)) {
    ok = bt_write_all(conn->fd, bytes, len);
  }
  if (conn && is_audio && !busy) {
    g_mutex_lock(&conn->tx_mutex);
    conn->streaming = FALSE;
    g_mutex_unlock(&conn->tx_mutex);
  }
  if (conn) bt_conn_unref(conn);
  if (busy) {
    fl_method_call_respond_error(call, "BUSY", "A prepared audio job is active",
                                NULL, NULL);
  } else {
    bt_respond_bool_sync(call, ok);
  }
}

static void bt_handle_prepared(FlMethodCall* call, FlValue* args,
                                gboolean cancel) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(call, "INVALID_ARGS", "Expected job map", NULL, NULL);
    return;
  }
  FlValue* address = fl_value_lookup_string(args, "address");
  FlValue* id = fl_value_lookup_string(args, "jobId");
  if (!address || fl_value_get_type(address) != FL_VALUE_TYPE_STRING ||
      !id || fl_value_get_type(id) != FL_VALUE_TYPE_INT ||
      fl_value_get_int(id) <= 0) {
    fl_method_call_respond_error(call, "INVALID_ARGS",
                                "Missing address or positive jobId", NULL, NULL);
    return;
  }
  BtPreparedJob* job = NULL;
  if (!cancel) {
    FlValue* data = fl_value_lookup_string(args, "data");
    FlValue* lengths = fl_value_lookup_string(args, "lengths");
    FlValue* samples = fl_value_lookup_string(args, "samples");
    FlValue* lead = fl_value_lookup_string(args, "leadMs");
    gboolean valid = data && fl_value_get_type(data) == FL_VALUE_TYPE_UINT8_LIST &&
        fl_value_get_length(data) <= 16 * 1024 * 1024 &&
        lengths && fl_value_get_type(lengths) == FL_VALUE_TYPE_INT32_LIST &&
        samples && fl_value_get_type(samples) == FL_VALUE_TYPE_INT32_LIST &&
        lead && fl_value_get_type(lead) == FL_VALUE_TYPE_INT &&
        fl_value_get_int(lead) >= 0 && fl_value_get_int(lead) <= 10000;
    gsize count = valid ? fl_value_get_length(lengths) : 0;
    valid = valid && count > 0 && count <= 200000 &&
        count == fl_value_get_length(samples);
    gint64 sum = 0;
    if (valid) {
      const gint32* sizes = fl_value_get_int32_list(lengths);
      const gint32* counts = fl_value_get_int32_list(samples);
      for (gsize i = 0; i < count; ++i) {
        if (sizes[i] < 1 || sizes[i] > 4096 || counts[i] <= 0 ||
            counts[i] > 3072 || counts[i] % 128 != 0) {
          valid = FALSE;
          break;
        }
        sum += sizes[i];
      }
      valid = valid && sum == static_cast<gint64>(fl_value_get_length(data));
    }
    if (!valid) {
      fl_method_call_respond_error(call, "INVALID_ARGS",
                                  "Invalid prepared audio job", NULL, NULL);
      return;
    }
    job = new BtPreparedJob();
    job->id = fl_value_get_int(id);
    job->lead_ms = fl_value_get_int(lead);
    job->data.assign(fl_value_get_uint8_list(data),
                     fl_value_get_uint8_list(data) + sum);
    job->lengths.assign(fl_value_get_int32_list(lengths),
                        fl_value_get_int32_list(lengths) + count);
    job->samples.assign(fl_value_get_int32_list(samples),
                        fl_value_get_int32_list(samples) + count);
  }

  BtPlugin* p = g_bt_plugin;
  g_autofree gchar* addr = bt_normalize_addr(fl_value_get_string(address));
  g_mutex_lock(&p->mutex);
  BtConnection* conn = static_cast<BtConnection*>(
      g_hash_table_lookup(p->audio_connections, addr));
  if (conn) bt_conn_ref(conn);
  g_mutex_unlock(&p->mutex);
  gboolean matched = FALSE;
  const char* error = "DISCONNECTED";
  if (conn) {
    g_mutex_lock(&conn->tx_mutex);
    if (cancel) {
      matched = conn->job && conn->job->id == fl_value_get_int(id);
      if (matched) {
        conn->job->cancelled = TRUE;
        g_cond_broadcast(&conn->tx_cond);
      }
    } else if (g_atomic_int_get(&conn->running)) {
      if (conn->job || conn->streaming) {
        error = "BUSY";
      } else {
        job->call = FL_METHOD_CALL(g_object_ref(call));
        conn->job = job;  // Registered synchronously, before returning.
        job = NULL;
        g_cond_broadcast(&conn->tx_cond);
      }
    }
    g_mutex_unlock(&conn->tx_mutex);
    bt_conn_unref(conn);
  }
  if (cancel) {
    bt_respond_bool_sync(call, matched);
  } else if (job) {
    delete job;
    fl_method_call_respond_error(call, error,
                                "Audio connection unavailable or busy", NULL, NULL);
  }
}

static void bt_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                              gpointer user_data) {
  if (!g_bt_plugin) {
    fl_method_call_respond_error(call, "DISCONNECTED", "Bluetooth plugin disposed",
                                NULL, NULL);
    return;
  }
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) v = fl_value_new_bool(bt_any_adapter_powered());
    fl_method_call_respond_success(call, v, NULL);

  } else if (strcmp(method, "getPairedDevices") == 0) {
    g_autoptr(FlValue) list = bt_enumerate_devices(FALSE);
    fl_method_call_respond_success(call, list, NULL);

  } else if (strcmp(method, "findCompatibleDevices") == 0) {
    g_autoptr(FlValue) list = bt_enumerate_devices(TRUE);
    fl_method_call_respond_success(call, list, NULL);

  } else if (strcmp(method, "getDeviceNames") == 0) {
    g_autoptr(FlValue) names = bt_enumerate_device_names();
    fl_method_call_respond_success(call, names, NULL);

  } else if (strcmp(method, "connect") == 0) {
    bt_handle_connect(call, args, FALSE);

  } else if (strcmp(method, "disconnect") == 0) {
    bt_handle_disconnect(call, args, FALSE);

  } else if (strcmp(method, "send") == 0) {
    bt_handle_send(call, args, FALSE);

  } else if (strcmp(method, "connectAudio") == 0) {
    bt_handle_connect(call, args, TRUE);

  } else if (strcmp(method, "disconnectAudio") == 0) {
    bt_handle_disconnect(call, args, TRUE);

  } else if (strcmp(method, "sendAudio") == 0) {
    bt_handle_send(call, args, TRUE);

  } else if (strcmp(method, "sendPreparedAudio") == 0) {
    bt_handle_prepared(call, args, FALSE);

  } else if (strcmp(method, "cancelPreparedAudio") == 0) {
    bt_handle_prepared(call, args, TRUE);

  } else {
    fl_method_call_respond_not_implemented(call, NULL);
  }
}

// ---------------------------------------------------------------------------
// Event channel stream handlers
// ---------------------------------------------------------------------------
static FlMethodErrorResponse* bt_data_listen(FlEventChannel* channel,
                                             FlValue* args,
                                             gpointer user_data) {
  if (g_bt_plugin) g_bt_plugin->data_listening = TRUE;
  return NULL;
}

static FlMethodErrorResponse* bt_data_cancel(FlEventChannel* channel,
                                             FlValue* args,
                                             gpointer user_data) {
  if (g_bt_plugin) g_bt_plugin->data_listening = FALSE;
  return NULL;
}

static FlMethodErrorResponse* bt_audio_listen(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  if (g_bt_plugin) g_bt_plugin->audio_listening = TRUE;
  return NULL;
}

static FlMethodErrorResponse* bt_audio_cancel(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  if (g_bt_plugin) g_bt_plugin->audio_listening = FALSE;
  return NULL;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
static void bt_view_destroyed(FlView*, gpointer user_data) {
  BtPlugin* p = static_cast<BtPlugin*>(user_data);
  if (g_bt_plugin == p) g_bt_plugin = NULL;
  g_mutex_lock(&p->mutex);
  p->stopping = TRUE;
  GHashTable* maps[] = {p->connections, p->audio_connections};
  for (GHashTable* map : maps) {
    GHashTableIter iter;
    gpointer value;
    g_hash_table_iter_init(&iter, map);
    while (g_hash_table_iter_next(&iter, NULL, &value))
      bt_conn_stop(static_cast<BtConnection*>(value));
    g_hash_table_remove_all(map);
  }
  g_mutex_unlock(&p->mutex);
  g_clear_object(&p->method_channel);
  g_clear_object(&p->data_channel);
  g_clear_object(&p->audio_channel);
  bt_plugin_unref(p);  // Outstanding connections/connect tasks retain their own refs.
}

void bluetooth_classic_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  if (g_bt_plugin) return;

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  BtPlugin* p = g_new0(BtPlugin, 1);
  p->refcount = 1;
  g_mutex_init(&p->mutex);
  p->connections = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                         (GDestroyNotify)bt_conn_unref);
  p->audio_connections = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                               (GDestroyNotify)bt_conn_unref);

  g_autoptr(FlStandardMethodCodec) mcodec = fl_standard_method_codec_new();
  p->method_channel = fl_method_channel_new(messenger, BT_METHOD_CHANNEL,
                                            FL_METHOD_CODEC(mcodec));
  fl_method_channel_set_method_call_handler(p->method_channel,
                                            bt_method_call_cb, NULL, NULL);

  g_autoptr(FlStandardMethodCodec) dcodec = fl_standard_method_codec_new();
  p->data_channel = fl_event_channel_new(messenger, BT_DATA_CHANNEL,
                                         FL_METHOD_CODEC(dcodec));
  fl_event_channel_set_stream_handlers(p->data_channel, bt_data_listen,
                                       bt_data_cancel, NULL, NULL);

  g_autoptr(FlStandardMethodCodec) acodec = fl_standard_method_codec_new();
  p->audio_channel = fl_event_channel_new(messenger, BT_AUDIO_CHANNEL,
                                          FL_METHOD_CODEC(acodec));
  fl_event_channel_set_stream_handlers(p->audio_channel, bt_audio_listen,
                                       bt_audio_cancel, NULL, NULL);

  g_bt_plugin = p;
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view) g_signal_connect(view, "destroy", G_CALLBACK(bt_view_destroyed), p);
}
