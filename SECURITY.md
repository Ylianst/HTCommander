# Security Policy

## Supported Versions

HTCommander is under active development. Security fixes are provided for the
latest published release.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Earlier releases | No |

Before reporting a vulnerability, please confirm that it affects the latest
release or the current `main` branch.

## Reporting a Vulnerability

Please do not report suspected security vulnerabilities in a public GitHub
issue, discussion, or pull request.

Email security reports to Ylian Saint-Hilaire at
[ylianst@gmail.com](mailto:ylianst@gmail.com). Sensitive reports should be
encrypted with the PGP public key below. This is the same key published in the
[MeshCentral security policy](https://github.com/Ylianst/MeshCentral/blob/master/SECURITY.md).

Include the following information when possible:

- The affected HTCommander version and operating system
- The affected radio model, protocol, or online service
- A description of the security impact
- Steps to reproduce the issue and a minimal proof of concept
- Relevant logs or screenshots with credentials, tokens, private messages,
  precise locations, and other sensitive information removed
- Whether the vulnerability is known to have been exploited or disclosed

You will receive an acknowledgement as soon as practical. Reports will be
investigated and disclosure coordinated according to severity, impact, and the
time needed to develop and distribute a fix. Please allow a reasonable amount
of time before publishing details.

## Scope

Security reports may include vulnerabilities involving:

- Credentials, passwords, API tokens, cryptographic keys, or private data
- Unauthorized radio control, transmission, local access, or remote access
- Bluetooth, WebSocket, HTTP, MQTT, APRS, Winlink, EchoLink, AllStarLink, BBS,
  torrent, update, import, export, and file-processing features
- Malicious packets, messages, files, URLs, radio configurations, or firmware
- HTCommander release packages, update packages, signing, and build systems
- Online services operated specifically for HTCommander

Ordinary crashes, feature requests, compatibility problems, and vulnerabilities
in third-party services or radio firmware without a demonstrated HTCommander
security impact should be reported to the appropriate public issue tracker or
vendor.

## Responsible Research

When investigating a potential vulnerability:

- Test only devices, accounts, call signs, and systems you own or are authorized
  to use.
- Follow applicable amateur-radio laws and licensing requirements.
- Use conducted, shielded, or otherwise controlled radio testing when
  practical.
- Do not disrupt repeaters, radio networks, internet services, or other users.
- Do not access, retain, or disclose another person's private information.
- Stop testing and report the issue if you gain unintended access to data or
  systems.

Good-faith research that follows this policy will not be treated as malicious
activity by the HTCommander project.

## PGP Public Key

```text
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: BCPG v1.56

mQMuBF2gC4sRCAClFNvMCCVW3ego3UHBQ6LhSenJfaZYhvn8gaGuemSQxqTI6bla
BTAv3aMtQnvqlSuadMMegb+FO6hnaQMlGvpVA1qpkSzgrPS5HrBD3H33J2Nj3i93
ZpDPpxdI0ehCj6IJPnl0GxGbpKIN8YpJUFl44wv1lMRFI1lgyb+dCoO60irYdNQB
PV85BI+DwPfOBFHunwR78nqMvpvsk9HaeHjEP7oXr952/7EazUowZsMlEfkYnw5S
+tLfpCoY3QWkektpJP40nMJSKQdV2NEuED99doA0X+7P1vsvFFFyMH69dnU2uSay
XCHpkAbntBy0BGmtF1RnTcOMv2V/LPXnlMdvAQCbmLQzNra3r163tcdRY0jSs+pZ
1L3w5tHNj2dzhfpa7wf/SIuds6QTr2LCN6miLoSVCRMMpT7d771b16GwQqWEXzN2
+h7dYqrssHPOa8FSUrPerz0+0eFcbMSm5/L/4KXWXoQthURv8aMP9E0iVoUYaaKB
7U+5vFEZbpoOZyZmTAjXQMSNZCft0azA82Q+G85euyicWtMv48yNVzUhkdh+M2ud
ohkXX2Aor1TqpBJoIeWke7j9D+Bo+lu61zPRx5ed9teUeLJCwqNEjlE+6gre5kxF
PoreAtn59QYcBIpzQEWVMbNFlDAR4jMyqIoKCGfBPiRw2V+kunbzqiGQEglIFfOt
6sTN/+CJh0ei976VDmE0Z1kMN+CNLgIjIw8fl02V9QgAnHcpqtVUxR4dbGOhVDq5
lWv+K75QQlWyXC2k+KboXcaCvH0WZEBACYzO0CfrZ5hP9BSkbj5usSUVGGHwEFAJ
t+/04KVY71fW281Ej5kGNaIKxeKsx6+hMo+UXb5ZM+6fANNNxs1cK95sTH6PjkyB
tsKxLoa3CV2v9mSE5JiKKt74R9nXVo7PXf6DizwAU2l30Lb6y6y0OdXdCCPAG8Ij
FrMgPu5MtjgsO5DnkZfUqDPWHhOgEPyOh3Ho+pvDhNYh5cm2eLQ8g5orzs2FHwbZ
DpAHwCdqrlcpBlKJ4W/MZdf1fg2PjqaTWm7ZFiGr91P0F6kltTLWbVKTjLdS0T+D
L7QnWWxpYW4gU2FpbnQtSGlsYWlyZSA8eWxpYW5zdEBnbWFpbC5jb20+iF4EExEI
AAYFAl2gC4sACgkQg7j/r4DH+kD/3gD+MRedlM53VzOtNOpS6mqDAxj1aWP90HN0
AqO6zuCTyGgBAJlunLFKH8IUetmQOhiohB8HVhdm/q4lKRDV7sHdplDyuMwEXaAL
ixACAJSU/sCV87he4oZUKzg2/IGl3QoDSbTCOd04dE1IjPjjHbi8t9M7Qau55aM8
ypFEsc7zMslL8Fc78EejrKmM3zsB/RU9XWFyrbQwRbaK6OHeEHC2E3AFaG0p09c6
d0kZloHuWyEsm5a/3PpbIM1eP9IESJXWCc+bQQt6DxLKHLmkKMwB/icWMg8uMJlx
aady8TEq7LH5oFVKsglnwuN1nIkecrf77TVkEqTjIxS6TiOup6zOnioFNKLYBAH0
WUnJEYFvx4OIXgQYEQgABgUCXaALiwAKCRCDuP+vgMf6QGFTAQCUj2gGwsFlN0eR
Wowv4eLcc3FwQ+lBElUctKg8vNFb0gD/ZWVWsWwKerNgNnf7RGD9mt8G2CKvdgGG
oZ2hPP2gU9w=
=roW4
-----END PGP PUBLIC KEY BLOCK-----
```