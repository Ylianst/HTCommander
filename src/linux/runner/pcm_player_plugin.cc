// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Native Linux PCM playback plugin implementation using the PulseAudio simple
// API (works on PulseAudio and PipeWire's pulse shim). See the header for the
// channel contract; it mirrors the Windows waveOut plugin.

#include "pcm_player_plugin.h"

#include <pulse/error.h>
#include <pulse/simple.h>

#include <string.h>

#define PCM_METHOD_CHANNEL "com.htcommander/pcm_player"
#define PCM_EVENT_CHANNEL "com.htcommander/pcm_player_feed"

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
typedef struct {
  guint8* data;
  gsize len;
} PcmChunk;

static void pcm_chunk_free(gpointer p) {
  PcmChunk* c = (PcmChunk*)p;
  g_free(c->data);
  g_free(c);
}

typedef struct {
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean listening;  // touched only on the platform (main) thread

  GMutex lock;
  GCond cond;
  GQueue* queue;          // of PcmChunk* (guarded by lock)
  gboolean running;       // playback thread should keep going
  GThread* thread;
  int sample_rate;
  int channels;
  gint64 queued_frames;   // frames queued but not yet handed to PulseAudio
  pa_simple* pa;          // playback stream (created in setup)
} PcmPlugin;

static PcmPlugin* g_pcm_plugin = NULL;

// ---------------------------------------------------------------------------
// Feed-callback dispatch (marshaled to the platform thread)
// ---------------------------------------------------------------------------
typedef struct {
  PcmPlugin* plugin;
  gint value;
} PcmFeedMsg;

static gboolean pcm_emit_feed_idle(gpointer user_data) {
  PcmFeedMsg* m = (PcmFeedMsg*)user_data;
  PcmPlugin* p = m->plugin;
  if (p && p->listening && p->event_channel) {
    g_autoptr(FlValue) v = fl_value_new_int(m->value);
    fl_event_channel_send(p->event_channel, v, NULL, NULL);
  }
  g_free(m);
  return G_SOURCE_REMOVE;
}

static void pcm_emit_feed(PcmPlugin* p, gint value) {
  PcmFeedMsg* m = g_new0(PcmFeedMsg, 1);
  m->plugin = p;
  m->value = value;
  g_idle_add(pcm_emit_feed_idle, m);
}

// ---------------------------------------------------------------------------
// Playback thread
// ---------------------------------------------------------------------------
static gpointer pcm_play_thread(gpointer user_data) {
  PcmPlugin* p = (PcmPlugin*)user_data;

  for (;;) {
    g_mutex_lock(&p->lock);
    while (p->running && g_queue_is_empty(p->queue)) {
      g_cond_wait(&p->cond, &p->lock);
    }
    if (!p->running) {
      g_mutex_unlock(&p->lock);
      break;
    }
    PcmChunk* c = (PcmChunk*)g_queue_pop_head(p->queue);
    pa_simple* pa = p->pa;
    int rate = p->sample_rate;
    int channels = p->channels;
    g_mutex_unlock(&p->lock);

    if (!c) continue;

    if (pa) {
      int err = 0;
      pa_simple_write(pa, c->data, c->len, &err);

      int frame_bytes = channels * 2;
      if (frame_bytes <= 0) frame_bytes = 2;
      gint64 frames = (gint64)c->len / frame_bytes;

      g_mutex_lock(&p->lock);
      p->queued_frames -= frames;
      if (p->queued_frames < 0) p->queued_frames = 0;
      gint64 queued = p->queued_frames;
      g_mutex_unlock(&p->lock);

      // Report roughly how many frames remain to be played: what is still in
      // our queue plus what PulseAudio has buffered but not yet rendered.
      pa_usec_t latency = pa_simple_get_latency(pa, &err);
      gint64 latency_frames = (gint64)latency * rate / 1000000;
      pcm_emit_feed(p, (gint)(queued + latency_frames));
    }

    pcm_chunk_free(c);
  }

  return NULL;
}

// ---------------------------------------------------------------------------
// setup / feed / release
// ---------------------------------------------------------------------------
static void pcm_release(PcmPlugin* p) {
  g_mutex_lock(&p->lock);
  p->running = FALSE;
  g_cond_signal(&p->cond);
  GThread* th = p->thread;
  p->thread = NULL;
  g_mutex_unlock(&p->lock);

  if (th) g_thread_join(th);

  g_mutex_lock(&p->lock);
  pa_simple* pa = p->pa;
  p->pa = NULL;
  PcmChunk* c;
  while ((c = (PcmChunk*)g_queue_pop_head(p->queue)) != NULL) {
    pcm_chunk_free(c);
  }
  p->queued_frames = 0;
  g_mutex_unlock(&p->lock);

  if (pa) pa_simple_free(pa);
}

static gboolean pcm_setup(PcmPlugin* p, int rate, int channels,
                          const char* device) {
  pcm_release(p);
  if (rate <= 0) rate = 32000;
  if (channels <= 0) channels = 1;

  pa_sample_spec ss;
  ss.format = PA_SAMPLE_S16LE;
  ss.rate = (uint32_t)rate;
  ss.channels = (uint8_t)channels;

  // An empty/NULL device name asks PulseAudio for the default output sink;
  // otherwise it is the sink name reported by `pactl list sinks`.
  const char* dev = (device && device[0] != '\0') ? device : NULL;

  int err = 0;
  pa_simple* pa = pa_simple_new(NULL, "HTCommander", PA_STREAM_PLAYBACK, dev,
                                "Radio Audio", &ss, NULL, NULL, &err);
  if (!pa && dev) {
    // The requested device may have disappeared; fall back to the default.
    g_warning("[PCM] pa_simple_new for device '%s' failed: %s; using default",
              dev, pa_strerror(err));
    pa = pa_simple_new(NULL, "HTCommander", PA_STREAM_PLAYBACK, NULL,
                       "Radio Audio", &ss, NULL, NULL, &err);
  }
  if (!pa) {
    g_warning("[PCM] pa_simple_new failed: %s", pa_strerror(err));
    return FALSE;
  }

  g_mutex_lock(&p->lock);
  p->pa = pa;
  p->sample_rate = rate;
  p->channels = channels;
  p->queued_frames = 0;
  p->running = TRUE;
  p->thread = g_thread_new("pcm-play", pcm_play_thread, p);
  g_mutex_unlock(&p->lock);
  return TRUE;
}

static gboolean pcm_feed(PcmPlugin* p, const guint8* data, gsize len) {
  if (!data || len == 0) return FALSE;

  g_mutex_lock(&p->lock);
  if (!p->pa || !p->running) {
    g_mutex_unlock(&p->lock);
    return FALSE;
  }
  PcmChunk* c = g_new0(PcmChunk, 1);
  c->data = (guint8*)g_malloc(len);
  memcpy(c->data, data, len);
  c->len = len;
  g_queue_push_tail(p->queue, c);

  int frame_bytes = p->channels * 2;
  if (frame_bytes <= 0) frame_bytes = 2;
  p->queued_frames += (gint64)len / frame_bytes;

  g_cond_signal(&p->cond);
  g_mutex_unlock(&p->lock);
  return TRUE;
}

// ---------------------------------------------------------------------------
// Method channel handler
// ---------------------------------------------------------------------------
static int pcm_int_arg(FlValue* args, const char* key, int fallback) {
  if (!args) return fallback;
  FlValue* v = fl_value_lookup_string(args, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return (int)fl_value_get_int(v);
  }
  return fallback;
}

static const char* pcm_string_arg(FlValue* args, const char* key) {
  if (!args) return NULL;
  FlValue* v = fl_value_lookup_string(args, key);
  if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(v);
  }
  return NULL;
}

static void pcm_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                          gpointer user_data) {
  PcmPlugin* p = g_pcm_plugin;
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "setLogLevel") == 0 || strcmp(method, "start") == 0) {
    g_autoptr(FlValue) v = fl_value_new_null();
    fl_method_call_respond_success(call, v, NULL);

  } else if (strcmp(method, "setup") == 0) {
    int rate = pcm_int_arg(args, "sampleRate", 32000);
    int chans = pcm_int_arg(args, "channels", 1);
    const char* device = pcm_string_arg(args, "deviceId");
    gboolean ok = pcm_setup(p, rate, chans, device);
    g_autoptr(FlValue) v = fl_value_new_bool(ok);
    fl_method_call_respond_success(call, v, NULL);

  } else if (strcmp(method, "setFeedThreshold") == 0) {
    g_autoptr(FlValue) v = fl_value_new_null();
    fl_method_call_respond_success(call, v, NULL);

  } else if (strcmp(method, "feed") == 0) {
    gboolean ok = FALSE;
    FlValue* b = args ? fl_value_lookup_string(args, "buffer") : NULL;
    if (b && fl_value_get_type(b) == FL_VALUE_TYPE_UINT8_LIST) {
      ok = pcm_feed(p, fl_value_get_uint8_list(b), fl_value_get_length(b));
    }
    g_autoptr(FlValue) v = fl_value_new_bool(ok);
    fl_method_call_respond_success(call, v, NULL);

  } else if (strcmp(method, "release") == 0) {
    pcm_release(p);
    g_autoptr(FlValue) v = fl_value_new_null();
    fl_method_call_respond_success(call, v, NULL);

  } else {
    fl_method_call_respond_not_implemented(call, NULL);
  }
}

// ---------------------------------------------------------------------------
// Event channel stream handlers
// ---------------------------------------------------------------------------
static FlMethodErrorResponse* pcm_feed_listen(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  if (g_pcm_plugin) g_pcm_plugin->listening = TRUE;
  return NULL;
}

static FlMethodErrorResponse* pcm_feed_cancel(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  if (g_pcm_plugin) g_pcm_plugin->listening = FALSE;
  return NULL;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
void pcm_player_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  if (g_pcm_plugin) return;

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  PcmPlugin* p = g_new0(PcmPlugin, 1);
  g_mutex_init(&p->lock);
  g_cond_init(&p->cond);
  p->queue = g_queue_new();
  p->sample_rate = 32000;
  p->channels = 1;

  g_autoptr(FlStandardMethodCodec) mcodec = fl_standard_method_codec_new();
  p->method_channel = fl_method_channel_new(messenger, PCM_METHOD_CHANNEL,
                                            FL_METHOD_CODEC(mcodec));
  fl_method_channel_set_method_call_handler(p->method_channel, pcm_method_cb,
                                            NULL, NULL);

  g_autoptr(FlStandardMethodCodec) ecodec = fl_standard_method_codec_new();
  p->event_channel = fl_event_channel_new(messenger, PCM_EVENT_CHANNEL,
                                          FL_METHOD_CODEC(ecodec));
  fl_event_channel_set_stream_handlers(p->event_channel, pcm_feed_listen,
                                       pcm_feed_cancel, NULL, NULL);

  g_pcm_plugin = p;
}
