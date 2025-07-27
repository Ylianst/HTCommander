# APRS Message Authentication

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-auth-aprs-messages.png?raw=true)

HT Commander has support for sending authenticated APRS messages. Two or more stations need to have a shared password and enter it in the HT Commander address book. Once setup, when sending messages to that station an additional 6 digit authentication code will be added to the message. If the receiving station has the same password, it will verify the message is authentic and display it in green. If the message does not match the password, it will be displayed in light orange.

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-auth-aprs-messages-config.png?raw=true)

To use this this feature, you need to add the password in the address book for the station you want to send authenticated messages to. The password is not sent over the air, it is only used to generate the authentication code. The authentication code is a 6 digit number that is generated from the password and the current time. The code changes every minute, so it is important to keep the clocks of the stations in sync. If the clocks are not in sync, the authentication code will not match and the message will not be authenticated. If someone replays a old message what was previously sent, the message will fail the authentication check. Other developers are welcome to also implement this, [the specification is here](https://github.com/Ylianst/HTCommander/blob/main/docs/Aprs-Auth-Specification.md).