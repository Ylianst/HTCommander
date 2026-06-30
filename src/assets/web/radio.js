const RadioCommandGroup = {
    BASIC: 2,
    EXTENDED: 10
};

const RadioBasicCommand = {
    UNKNOWN: 0,
    GET_DEV_ID: 1,
    SET_REG_TIMES: 2,
    GET_REG_TIMES: 3,
    GET_DEV_INFO: 4,
    READ_STATUS: 5,
    REGISTER_NOTIFICATION: 6, // No Response
    CANCEL_NOTIFICATION: 7,
    GET_NOTIFICATION: 8,
    EVENT_NOTIFICATION: 9,
    READ_SETTINGS: 10,
    WRITE_SETTINGS: 11, // No Response
    STORE_SETTINGS: 12,
    READ_RF_CH: 13, // No Response
    WRITE_RF_CH: 14,
    GET_IN_SCAN: 15,
    SET_IN_SCAN: 16,
    SET_REMOTE_DEVICE_ADDR: 17,
    GET_TRUSTED_DEVICE: 18,
    DEL_TRUSTED_DEVICE: 19,
    GET_HT_STATUS: 20,
    SET_HT_ON_OFF: 21,
    GET_VOLUME: 22,
    SET_VOLUME: 23,
    RADIO_GET_STATUS: 24,
    RADIO_SET_MODE: 25,
    RADIO_SEEK_UP: 26,
    RADIO_SEEK_DOWN: 27,
    RADIO_SET_FREQ: 28,
    READ_ADVANCED_SETTINGS: 29,
    WRITE_ADVANCED_SETTINGS: 30,
    HT_SEND_DATA: 31,
    SET_POSITION: 32,
    READ_BSS_SETTINGS: 33,
    WRITE_BSS_SETTINGS: 34,
    FREQ_MODE_SET_PAR: 35,
    FREQ_MODE_GET_STATUS: 36,
    READ_RDA1846S_AGC: 37,
    WRITE_RDA1846S_AGC: 38,
    READ_FREQ_RANGE: 39,
    WRITE_DE_EMPH_COEFFS: 40,
    STOP_RINGING: 41,
    SET_TX_TIME_LIMIT: 42,
    SET_IS_DIGITAL_SIGNAL: 43,
    SET_HL: 44,
    SET_DID: 45,
    SET_IBA: 46,
    GET_IBA: 47,
    SET_TRUSTED_DEVICE_NAME: 48,
    SET_VOC: 49,
    GET_VOC: 50,
    SET_PHONE_STATUS: 51,
    READ_RF_STATUS: 52,
    PLAY_TONE: 53,
    GET_DID: 54,
    GET_PF: 55,
    SET_PF: 56,
    RX_DATA: 57,
    WRITE_REGION_CH: 58,
    WRITE_REGION_NAME: 59,
    SET_REGION: 60, // No Response
    SET_PP_ID: 61,
    GET_PP_ID: 62,
    READ_ADVANCED_SETTINGS2: 63,
    WRITE_ADVANCED_SETTINGS2: 64,
    UNLOCK: 65,
    DO_PROG_FUNC: 66,
    SET_MSG: 67,
    GET_MSG: 68,
    BLE_CONN_PARAM: 69,
    SET_TIME: 70,
    SET_APRS_PATH: 71,
    GET_APRS_PATH: 72,
    READ_REGION_NAME: 73,
    SET_DEV_ID: 74,
    GET_PF_ACTIONS: 75,
    GET_POSITION: 76
};

const RadioExtendedCommand = {
    UNKNOWN: 0,
    GET_BT_SIGNAL: 769,
    UNKNOWN_01: 1600,
    UNKNOWN_02: 1601,
    UNKNOWN_03: 1602,
    UNKNOWN_04: 16385,
    UNKNOWN_05: 16386,
    GET_DEV_STATE_VAR: 16387,
    DEV_REGISTRATION: 1825
}

const RadioPowerStatus = {
    UNKNOWN: 0,
    BATTERY_LEVEL: 1,
    BATTERY_VOLTAGE: 2,
    RC_BATTERY_LEVEL: 3,
    BATTERY_LEVEL_AS_PERCENTAGE: 4
}

const RadioNotification = {
    UNKNOWN: 0,
    HT_STATUS_CHANGED: 1,
    DATA_RXD: 2,  // Received APRS or BSS Message
    NEW_INQUIRY_DATA: 3,
    RESTORE_FACTORY_SETTINGS: 4,
    HT_CH_CHANGED: 5,
    HT_SETTINGS_CHANGED: 6,
    RINGING_STOPPED: 7,
    RADIO_STATUS_CHANGED: 8,
    USER_ACTION: 9,
    SYSTEM_EVENT: 10,
    BSS_SETTINGS_CHANGED: 11,
    DATA_TXD: 12,
    POSITION_CHANGE: 13
}

const RadioChannelType = {
    OFF: 0,
    A: 1,
    B: 2
}

const RadioModulationType = {
    FM: 0,
    AM: 1,
    DMR: 2
}

const RadioBandwidthType = {
    NARROW: 0,
    WIDE: 1
}

const RadioUpdateNotification = {
    State: 1,
    ChannelInfo: 2,
    BatteryLevel: 3,
    BatteryVoltage: 4,
    RcBatteryLevel: 5,
    BatteryAsPercentage: 6,
    HtStatus: 7,
    Settings: 8,
    Volume: 9,
    AllChannelsLoaded: 10,
    RegionChange: 11,
    BssSettings: 12
}

const RadioState = {
    Disconnected: 1,
    Connecting: 2,
    Connected: 3,
    MultiRadioSelect: 4,
    UnableToConnect: 5,
    BluetoothNotAvailable: 6,
    NotRadioFound: 7,
    AccessDenied: 8
}

const RadioCommandState = {
    SUCCESS: 0,
    NOT_SUPPORTED: 1,
    NOT_AUTHENTICATED: 2,
    INSUFFICIENT_RESOURCES: 3,
    AUTHENTICATING: 4,
    INVALID_PARAMETER: 5,
    INCORRECT_STATE: 6,
    IN_PROGRESS: 7
}
class RadioHtStatus {
    // 2 first bytes
    is_power_on;
    is_in_tx;
    is_sq;
    is_in_rx;
    double_channel;
    is_scan;
    is_radio;
    curr_ch_id_lower;
    is_gps_locked;
    is_hfp_connected;
    is_aoc_connected;
    channel_id;
    name_str;
    curr_ch_id;

    // Two next byte if present
    rssi;
    curr_region;
    curr_channel_id_upper;

    /**
     * Constructs a RadioHtStatus object from a byte array (Uint8Array).
     * @param {Uint8Array} msg - The byte array containing the radio status data.
     */
    constructor(msg) {
        if (!(msg instanceof Uint8Array)) {
            throw new Error("Input must be a Uint8Array.");
        }

        // Two first bytes
        this.is_power_on = (msg[5] & 0x80) !== 0;
        this.is_in_tx = (msg[5] & 0x40) !== 0;
        this.is_sq = (msg[5] & 0x20) !== 0;
        this.is_in_rx = (msg[5] & 0x10) !== 0;
        this.double_channel = (msg[5] & 0x0c) >> 2;
        this.is_scan = (msg[5] & 0x02) !== 0;
        this.is_radio = (msg[5] & 0x01) !== 0;
        this.curr_ch_id_lower = msg[6] >> 4;
        this.is_gps_locked = (msg[6] & 0x08) !== 0;
        this.is_hfp_connected = (msg[6] & 0x04) !== 0;
        this.is_aoc_connected = (msg[6] & 0x02) !== 0;

        // Default values for properties that might not be in the message
        this.rssi = 0;
        this.curr_region = 0;
        this.curr_channel_id_upper = 0;
        this.channel_id = 0;
        this.name_str = "";

        // Next two bytes
        if (msg.length === 9) {
            this.rssi = msg[7] >> 4; // 0 to 16
            this.curr_region = ((msg[7] & 0x0f) << 2) + (msg[8] >> 6);
            this.curr_channel_id_upper = (msg[8] & 0x3c) >> 2;
        }

        this.curr_ch_id = (this.curr_channel_id_upper << 4) + this.curr_ch_id_lower;
    }

    /**
     * Creates a deep copy of another RadioHtStatus object.
     * @param {RadioHtStatus} other - The RadioHtStatus object to copy from.
     */
    static deepCopy(other) {
        if (!(other instanceof RadioHtStatus)) {
            throw new Error("Input must be an instance of RadioHtStatus.");
        }

        const newStatus = new RadioHtStatus(new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0, 0]));

        // Two first bytes
        newStatus.is_power_on = other.is_power_on;
        newStatus.is_in_tx = other.is_in_tx;
        newStatus.is_sq = other.is_sq;
        newStatus.is_in_rx = other.is_in_rx;
        newStatus.double_channel = other.double_channel;
        newStatus.is_scan = other.is_scan;
        newStatus.is_radio = other.is_radio;
        newStatus.curr_ch_id_lower = other.curr_ch_id_lower;
        newStatus.is_gps_locked = other.is_gps_locked;
        newStatus.is_hfp_connected = other.is_hfp_connected;
        newStatus.is_aoc_connected = other.is_aoc_connected;
        newStatus.channel_id = other.channel_id;
        newStatus.name_str = other.name_str;
        newStatus.curr_ch_id = other.curr_ch_id;

        // Next two bytes
        newStatus.rssi = other.rssi;
        newStatus.curr_region = other.curr_region;
        newStatus.curr_channel_id_upper = other.curr_channel_id_upper;

        return newStatus;
    }

    /**
     * Converts the RadioHtStatus object back into a Uint8Array.
     * @returns {Uint8Array} The byte array representation of the radio status.
     */
    ToByteArray() {
        const msg = new Uint8Array(4);

        // Serialize the first two bytes (corresponding to C# msg[5] and msg[6] in constructor)
        msg[0] = 0;
        msg[0] |= this.is_power_on ? 0x80 : 0x00;
        msg[0] |= this.is_in_tx ? 0x40 : 0x00;
        msg[0] |= this.is_sq ? 0x20 : 0x00;
        msg[0] |= this.is_in_rx ? 0x10 : 0x00;
        msg[0] |= (this.double_channel & 0x03) << 2; // Ensure only 2 bits are used
        msg[0] |= this.is_scan ? 0x02 : 0x00;
        msg[0] |= this.is_radio ? 0x01 : 0x00;

        msg[1] = 0;
        msg[1] |= (this.curr_ch_id_lower & 0x0F) << 4; // Ensure only 4 bits are used
        msg[1] |= this.is_gps_locked ? 0x08 : 0x00;
        msg[1] |= this.is_hfp_connected ? 0x04 : 0x00;
        msg[1] |= this.is_aoc_connected ? 0x02 : 0x00;

        // Serialize the next two bytes if values are present (corresponding to C# msg[7] and msg[8] in constructor)
        msg[2] = 0;
        msg[2] |= (this.rssi & 0x0F) << 4; // Ensure only 4 bits are used
        msg[2] |= (this.curr_region >> 2) & 0x0F;

        msg[3] = 0;
        msg[3] |= (this.curr_region & 0x03) << 6;
        msg[3] |= (this.curr_channel_id_upper & 0x0F) << 2; // Ensure only 4 bits are used for upper channel ID

        return msg;
    }
}

class RadioDevInfo {
    constructor(msg) {
        // Ensure msg is a Uint8Array or similar byte array
        if (!(msg instanceof Uint8Array) && !Array.isArray(msg)) {
            throw new Error("Input 'msg' must be a byte array (e.g., Uint8Array or Array).");
        }

        // 0002 8004 00060104010085d0681e54

        this.vendor_id = msg[5];
        this.product_id = Utils.getShort(msg, 6);
        this.hw_ver = msg[8];
        this.soft_ver = Utils.getShort(msg, 9);
        this.soft_ver_str = ((this.soft_ver >> 8) & 0xF) + "." + ((this.soft_ver >> 4) & 0xF) + "." + (this.soft_ver & 0xF);

        this.support_radio = ((msg[11] & 0x80) !== 0);
        this.support_medium_power = ((msg[11] & 0x40) !== 0);
        this.fixed_loc_speaker_vol = ((msg[11] & 0x20) !== 0);
        this.not_support_soft_power_ctrl = ((msg[11] & 0x10) !== 0);
        this.have_no_speaker = ((msg[11] & 0x08) !== 0);
        this.have_hm_speaker = ((msg[11] & 0x04) !== 0);
        this.region_count = ((msg[11] & 0x03) << 4) + ((msg[12] & 0xF0) >> 4);
        this.support_noaa = ((msg[12] & 0x08) !== 0);
        this.gmrs = ((msg[12] & 0x04) !== 0);
        this.support_vfo = ((msg[12] & 0x02) !== 0);
        this.support_dmr = ((msg[12] & 0x01) !== 0);
        this.channel_count = msg[13];
        this.freq_range_count = (msg[14] & 0xF0) >> 4;
    }
}

const Utils = {
    getInt: (arr, offset) => { return ((arr[offset] & 0x3F) << 24) | (arr[offset + 1] << 16) | (arr[offset + 2] << 8) | arr[offset + 3]; },
    setInt: (arr, offset, value) => { arr[offset] = (value >> 24) & 0x3F; arr[offset + 1] = (value >> 16) & 0xFF; arr[offset + 2] = (value >> 8) & 0xFF; arr[offset + 3] = value & 0xFF; },
    getShort: (arr, offset) => { return (arr[offset] << 8) | arr[offset + 1]; },
    setShort: (arr, offset, value) => { arr[offset] = (value >> 8) & 0xFF; arr[offset + 1] = value & 0xFF; }
};

class BluetoothCommandQueue {
    constructor() {
        this.queue = [];
        this.executing = false;
    }

    enqueue(commandFn) {
        return new Promise((resolve, reject) => {
            this.queue.push(() => commandFn().then(resolve).catch(reject));
            this.runNext();
        });
    }

    async runNext() {
        if (this.executing || this.queue.length === 0) return;

        this.executing = true;
        const command = this.queue.shift();
        try {
            await command();
        } finally {
            this.executing = false;
            this.runNext();
        }
    }
}

// RadioChannelInfo class
class RadioChannelInfo {
    constructor(msg = null) {
        if (msg) {
            this.channel_id = msg[5];
            this.tx_mod = (msg[6] >> 6);
            this.tx_freq = Utils.getInt(msg, 6) & 0x3FFFFFFF;
            this.rx_mod = (msg[10] >> 6);
            this.rx_freq = Utils.getInt(msg, 10) & 0x3FFFFFFF;
            this.tx_sub_audio = Utils.getShort(msg, 14);
            this.rx_sub_audio = Utils.getShort(msg, 16);

            const flags1 = msg[18];
            this.scan = !!(flags1 & 0x80);
            this.tx_at_max_power = !!(flags1 & 0x40);
            this.talk_around = !!(flags1 & 0x20);
            this.bandwidth = (flags1 & 0x10) ? RadioBandwidthType.WIDE : RadioBandwidthType.NARROW;
            this.pre_de_emph_bypass = !!(flags1 & 0x08);
            this.sign = !!(flags1 & 0x04);
            this.tx_at_med_power = !!(flags1 & 0x02);
            this.tx_disable = !!(flags1 & 0x01);

            const flags2 = msg[19];
            this.fixed_freq = !!(flags2 & 0x80);
            this.fixed_bandwidth = !!(flags2 & 0x40);
            this.fixed_tx_power = !!(flags2 & 0x20);
            this.mute = !!(flags2 & 0x10);

            const nameBytes = msg.slice(20, 30);
            this.name_str = new TextDecoder().decode(nameBytes).replace(/\0.*$/, '').trim();
        }
    }

    clone() {
        const copy = new RadioChannelInfo();
        Object.assign(copy, this);
        return copy;
    }

    equals(other) {
        return other &&
            this.channel_id === other.channel_id &&
            this.tx_mod === other.tx_mod &&
            this.tx_freq === other.tx_freq &&
            this.rx_mod === other.rx_mod &&
            this.rx_freq === other.rx_freq &&
            this.tx_sub_audio === other.tx_sub_audio &&
            this.rx_sub_audio === other.rx_sub_audio &&
            this.scan === other.scan &&
            this.tx_at_max_power === other.tx_at_max_power &&
            this.talk_around === other.talk_around &&
            this.bandwidth === other.bandwidth &&
            this.pre_de_emph_bypass === other.pre_de_emph_bypass &&
            this.sign === other.sign &&
            this.tx_at_med_power === other.tx_at_med_power &&
            this.tx_disable === other.tx_disable &&
            this.fixed_freq === other.fixed_freq &&
            this.fixed_bandwidth === other.fixed_bandwidth &&
            this.fixed_tx_power === other.fixed_tx_power &&
            this.mute === other.mute &&
            this.name_str === other.name_str;
    }

    toByteArray() {
        const r = new Uint8Array(30);
        r[0] = this.channel_id;

        Utils.setInt(r, 1, this.tx_freq);
        r[1] |= (this.tx_mod & 0x03) << 6;

        Utils.setInt(r, 5, this.rx_freq);
        r[5] |= (this.rx_mod & 0x03) << 6;

        Utils.setShort(r, 9, this.tx_sub_audio);
        Utils.setShort(r, 11, this.rx_sub_audio);

        if (this.scan) r[13] |= 0x80;
        if (this.tx_at_max_power) r[13] |= 0x40;
        if (this.talk_around) r[13] |= 0x20;
        if (this.bandwidth === RadioBandwidthType.WIDE) r[13] |= 0x10;
        if (this.pre_de_emph_bypass) r[13] |= 0x08;
        if (this.sign) r[13] |= 0x04;
        if (this.tx_at_med_power) r[13] |= 0x02;
        if (this.tx_disable) r[13] |= 0x01;

        if (this.fixed_freq) r[14] |= 0x80;
        if (this.fixed_bandwidth) r[14] |= 0x40;
        if (this.fixed_tx_power) r[14] |= 0x20;
        if (this.mute) r[14] |= 0x10;

        const nameBytes = new TextEncoder().encode(this.name_str);
        r.set(nameBytes.slice(0, 10), 15);

        return r;
    }
}
class RadioSettings {
    constructor(param) {
        this.rawData = null;
        this.channel_a = 0;
        this.channel_b = 0;
        this.scan = false;
        this.aghfp_call_mode = false;
        this.double_channel = 0;
        this.squelch_level = 0; // 0 to 9
        this.tail_elim = false;
        this.auto_relay_en = false;
        this.auto_power_on = false;
        this.keep_aghfp_link = false;
        this.mic_gain = 0;
        this.tx_hold_time = 0;
        this.tx_time_limit = 0;
        this.local_speaker = 0; // 0 to 3
        this.bt_mic_gain = 0; // 0 to 7
        this.adaptive_response = false;
        this.dis_tone = false;
        this.power_saving_mode = false;
        this.auto_power_off = 0; // 0 to 8
        this.auto_share_loc_ch = 0; // 5 bits
        this.hm_speaker = 0; // 2 bits
        this.positioning_system = 0; // 4 bits
        this.time_offset = 0; // 6 bits
        this.use_freq_range_2 = false;
        this.ptt_lock = false;
        this.leading_sync_bit_en = false;
        this.pairing_at_power_on = false;
        this.screen_timeout = 0; // 5 bits
        this.vfo_x = 0; // 2 bits
        this.imperial_unit = false;
        this.wx_mode = 0; // 2 bits
        this.noaa_ch = 0; // 4 bits
        this.vfol_tx_power_x = 0; // 2 bits
        this.vfo2_tx_power_x = 0; // 2 bits
        this.dis_digital_mute = false;
        this.signaling_ecc_en = false;
        this.ch_data_lock = false;
        this.vfo1_mod_freq_x = 0; // 4 bytes
        this.vfo2_mod_freq_x = 0; // 4 bytes

        if (param instanceof RadioSettings) {
            // Clone constructor
            this.rawData = param.rawData ? new Uint8Array(param.rawData) : null; // Deep copy rawData if it exists
            this.channel_a = param.channel_a;
            this.channel_b = param.channel_b;
            this.scan = param.scan;
            this.aghfp_call_mode = param.aghfp_call_mode;
            this.double_channel = param.double_channel;
            this.squelch_level = param.squelch_level;
            this.tail_elim = param.tail_elim;
            this.auto_relay_en = param.auto_relay_en;
            this.auto_power_on = param.auto_power_on;
            this.keep_aghfp_link = param.keep_aghfp_link;
            this.mic_gain = param.mic_gain;
            this.tx_hold_time = param.tx_hold_time;
            this.tx_time_limit = param.tx_time_limit;
            this.local_speaker = param.local_speaker;
            this.bt_mic_gain = param.bt_mic_gain;
            this.adaptive_response = param.adaptive_response;
            this.dis_tone = param.dis_tone;
            this.power_saving_mode = param.power_saving_mode;
            this.auto_power_off = param.auto_power_off;
            this.auto_share_loc_ch = param.auto_share_loc_ch;
            this.hm_speaker = param.hm_speaker;
            this.positioning_system = param.positioning_system;
            this.time_offset = param.time_offset;
            this.use_freq_range_2 = param.use_freq_range_2;
            this.ptt_lock = param.ptt_lock;
            this.leading_sync_bit_en = param.leading_sync_bit_en;
            this.pairing_at_power_on = param.pairing_at_power_on;
            this.screen_timeout = param.screen_timeout;
            this.vfo_x = param.vfo_x;
            this.imperial_unit = param.imperial_unit;
            this.wx_mode = param.wx_mode;
            this.noaa_ch = param.noaa_ch;
            this.vfol_tx_power_x = param.vfol_tx_power_x;
            this.vfo2_tx_power_x = param.vfo2_tx_power_x;
            this.dis_digital_mute = param.dis_digital_mute;
            this.signaling_ecc_en = param.signaling_ecc_en;
            this.ch_data_lock = param.ch_data_lock;
            this.vfo1_mod_freq_x = param.vfo1_mod_freq_x;
            this.vfo2_mod_freq_x = param.vfo2_mod_freq_x;
        } else if (param instanceof Uint8Array) {
            // Constructor from byte array (Uint8Array)
            const msg = param;
            this.rawData = new Uint8Array(msg); // Store a copy of the raw data

            this.channel_a = ((msg[5] & 0xF0) >> 4) + (msg[14] & 0xF0);
            this.channel_b = (msg[5] & 0x0F) + ((msg[14] & 0x0F) << 4);

            this.scan = (msg[6] & 0x80) !== 0;
            this.aghfp_call_mode = (msg[6] & 0x40) !== 0;
            this.double_channel = (msg[6] & 0x30) >> 4;
            this.squelch_level = (msg[6] & 0x0F);

            this.tail_elim = (msg[7] & 0x80) !== 0;
            this.auto_relay_en = (msg[7] & 0x40) !== 0;
            this.auto_power_on = (msg[7] & 0x20) !== 0;
            this.keep_aghfp_link = (msg[7] & 0x10) !== 0;
            this.mic_gain = (msg[7] & 0x0E) >> 1;
            this.tx_hold_time = ((msg[7] & 0x01) << 4) + ((msg[8] & 0xE0) >> 4);
            this.tx_time_limit = (msg[8] & 0x1F);

            this.local_speaker = msg[9] >> 6;
            this.bt_mic_gain = (msg[9] & 0x38) >> 3;
            this.adaptive_response = (msg[9] & 0x04) !== 0;
            this.dis_tone = (msg[9] & 0x02) !== 0;
            this.power_saving_mode = (msg[9] & 0x01) !== 0;

            this.auto_power_off = msg[10] >> 4;
            this.auto_share_loc_ch = (msg[10] & 0x1F);

            this.hm_speaker = msg[11] >> 6;
            this.positioning_system = (msg[11] & 0x3C) >> 2;
            this.time_offset = ((msg[11] & 0x03) << 4) + ((msg[12] & 0xF0) >> 4);
            this.use_freq_range_2 = (msg[12] & 0x08) !== 0;
            this.ptt_lock = (msg[12] & 0x04) !== 0;
            this.leading_sync_bit_en = (msg[12] & 0x02) !== 0;
            this.pairing_at_power_on = (msg[12] & 0x01) !== 0;

            this.screen_timeout = msg[13] >> 3;
            this.vfo_x = (msg[13] & 0x06) >> 1;
            this.imperial_unit = (msg[13] & 0x01) !== 0;

            this.wx_mode = msg[15] >> 6;
            this.noaa_ch = (msg[15] & 0x3C) >> 2;
            this.vfol_tx_power_x = (msg[15] & 0x03);

            this.vfo2_tx_power_x = (msg[16] >> 6);
            this.dis_digital_mute = (msg[16] & 0x20) !== 0;
            this.signaling_ecc_en = (msg[16] & 0x10) !== 0;
            this.ch_data_lock = (msg[16] & 0x08) !== 0;

            if (msg.length >= 25) { // Ensure enough bytes for vfo1_mod_freq_x and vfo2_mod_freq_x
                const dataView = new DataView(msg.buffer, msg.byteOffset);
                this.vfo1_mod_freq_x = dataView.getUint32(17, true); // true for little-endian
                this.vfo2_mod_freq_x = dataView.getUint32(21, true); // true for little-endian
            }
        } else {
            // Default constructor or no arguments
            // All properties are already initialized to their default values
        }
    }

    ToByteArray() {
        if (!this.rawData) {
            console.warn("rawData is not initialized. Cannot create byte array from original rawData slice.");
            return new Uint8Array(0);
        }
        // Creates a new Uint8Array from the slice of rawData
        // In JavaScript, slice on Uint8Array creates a new array
        return this.rawData.slice(5, this.rawData.length);
    }

    ToByteArray(cha, chb, xdouble_channel, xscan, xsquelch) {
        if (!this.rawData) {
            console.warn("rawData is not initialized. Cannot create byte array based on it.");
            this.rawData = new Uint8Array(25); // Or handle this more robustly
        }

        const buf = new Uint8Array(this.rawData.length - 5);
        // Copy a slice of rawData.slice(5) into buf
        buf.set(this.rawData.slice(5, this.rawData.length));

        buf[0] = ((cha & 0x0F) << 4) | (chb & 0x0F);
        // In C#, `(byte)` cast truncates to 8 bits. In JS, bitwise ops inherently handle this.
        buf[1] = (xscan ? 0x80 : 0) | (this.aghfp_call_mode ? 0x40 : 0) | ((xdouble_channel & 0x03) << 4) | (xsquelch & 0x0F);
        buf[9] = (cha & 0xF0) | ((chb & 0x0F) >> 4);
        return buf;
    }
}
