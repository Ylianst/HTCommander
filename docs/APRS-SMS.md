# APRS SMS

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-aprs-sms.png?raw=true)

If you setup HT Commander with a callsign and allow transmit you can send SMS messages to normal mobile phones using APRS. Before doing this, you must have the recipient of the SMS message opt-in for this service. Go to [aprs.wiki](https://aprs.wiki/) and opt in. The service will send an SMS message to the phone and you will need to confirm with a SMS reply.

Once opted-in, connect HT Commander to the radio and in the [APRS tab](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS.md), there is a menu on the upper right where you can click "SMS Message...". Note that everything sent to the gateway is transmitted without any encryption or authentication.

## Guided operations

The "SMS Message..." dialog guides you through the six operations supported by the [aprs.wiki](https://aprs.wiki/howto/) gateway. Pick one from the **Operation** drop-down and the dialog shows only the fields it needs:

1. **Send a message to a phone number** — enter the destination number and your message. The app sends `@<number> <message>` to the gateway.
2. **Send a message to an alias** — enter an alias you created earlier and your message. The app sends `@<alias> <message>`.
3. **Create an alias** — map a short alias to a phone number so you don't have to type the number (and it is masked on the air). The app sends `#alias #add <alias> <number>`.
4. **Remove an alias** — delete an alias you created. The app sends `#alias #remove <alias> <number>`.
5. **Check for missed messages** — ask the gateway to resend anything you may have missed. The app sends `APRSM`.
6. **Delete missed messages** — clear all missed messages queued for your callsign (every SSID). The app sends `del`.

### Limitations

- Phone numbers use **10 digits** in the USA, Canada & Puerto Rico, **11** in Australia and **12** in the UK. Do **not** add a leading `1`.
- Alias management uses the same 10-digit numbers (UK: 12 digits), with no leading `1`.
- Aliases are tied to your callsign (not your SSID), so they work from any of your stations.
- "Delete missed messages" cannot be undone.
