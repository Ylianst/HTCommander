# Voice

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-voice.png?raw=true)

Handi-Talky Commander has built-in speech recognition capabilities with integration of Open AI's Whisper. Radio audio will be run into a neural-network language model to convert into text and the results are quite impressive. A powerful CPU with AVX support is required.

From within Handi-Talky Commander you can select and download one of the Whisper models. The larger the model, the better the results but also the more CPU power is required.

- Tiny, 77.7 MB
- Tiny.en, 77.7 MB, English Only
- Base, 148 MB
- Base.en, 148 MB, English Only (Recommended)
- Small, 488 MB
- Small.en, 488 MB, English Only
- Medium, 1.53 GB
- Medium.en, 1.53 GB, English Only

The English-only models are best if you intend to only listen to English conversations, otherwise, the normal models support a large range of languages. You can help the model out by selecting the language you will be listening to in the Settings panel, this will give a hint to the model to focus that selected language.

Once enabled, the voice recognition will run when the radio no longer receives a signal or every 20 to 30 seconds.

In addition, there is support for text-to-speech (TTS) using the Microsoft Speech API. So, you can type a message and it will be read on the radio.

## Exporting Comms Conversations

Open the **Comms** tab menu and select **Save as CSV...** or **Save as TXT...**.
Both formats save a snapshot of all messages currently in the tab, in chronological
order, using UTF-8 and ISO 8601 UTC timestamps. Export is disabled when the tab is
empty. Messages hidden from Comms (such as dedicated APRS channel traffic) are not
included. Live, partially decoded text is saved as it appears at export time.

CSV is the recommended format for importing into other software. It has a header
row and the following columns:

`timestamp_utc`, `direction`, `type`, `channel`, `source`, `destination`, `text`,
`latitude`, `longitude`, `duration_seconds`, `filename`, `image_path`, `wpm`,
`key_type`, `authentication`, `id`, `route`.

Direction is `sent` or `received`; unavailable fields are empty. All fields are
quoted, embedded quotes are doubled, and records use CRLF line endings. Text
containing commas, quotes or line breaks is preserved inside its quoted field;
importers must use a CSV parser rather than split the file into lines. Coordinates
are decimal degrees, and authentication is `unknown`, `none`, `success` or `failed`.
Message IDs are identifiers for the displayed entries, not globally unique IDs.
Message text is preserved exactly, including formula-like text; when importing
untrusted conversations into a spreadsheet, import text columns as text rather
than evaluating formulas.

TXT provides a readable transcript with each message's timestamp, direction,
available metadata and text. Both formats include media captions and local file
references, but do not embed images or audio. Exported files can contain callsigns,
locations, message contents and local paths; review them before sharing.
