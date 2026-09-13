# APRS Frequencies by Location

This is a practical reference for commonly used APRS radio frequencies. APRS frequency use is determined by local and national amateur-radio band plans, so operators should verify the current local plan before transmitting.

## Terrestrial VHF APRS

Most entries use 1200-baud Bell 202 AFSK unless otherwise noted.

| Location | Frequency | Notes |
| --- | ---: | --- |
| Argentina | 144.930 MHz | 144.390 MHz is also reported in use |
| Australia | 145.175 MHz | WIA band-plan frequency |
| Austria | 144.800 MHz | IARU Region 1 |
| Belgium | 144.800 MHz | IARU Region 1 |
| Brazil | 145.570 MHz | Local references may differ |
| Canada | 144.390 MHz | IARU Region 2 |
| Chile | 144.390 MHz | IARU Region 2 |
| China | 144.640 MHz | IARU Region 3 |
| Colombia | 144.390 MHz | IARU Region 2 |
| Czech Republic | 144.800 MHz | IARU Region 1 |
| Denmark | 144.800 MHz | IARU Region 1 |
| Finland | 144.800 MHz | IARU Region 1 |
| France | 144.800 MHz | IARU Region 1 |
| Germany | 144.800 MHz | IARU Region 1 |
| Greece | 144.800 MHz | IARU Region 1 |
| Hong Kong | 144.640 MHz | IARU Region 3 |
| Hungary | 144.800 MHz | IARU Region 1 |
| Indonesia | 144.390 MHz | IARU Region 3 |
| Ireland | 144.800 MHz | IARU Region 1 |
| Italy | 144.800 MHz | IARU Region 1 |
| Japan | 144.660 MHz | 1200 baud |
| Netherlands | 432.500 MHz | 70 cm local APRS use |
| Malaysia | 144.390 MHz | IARU Region 3 |
| Mexico | 144.390 MHz | IARU Region 2 |
| Netherlands | 144.800 MHz | Common 2 m APRS frequency |
| New Zealand | 144.575 MHz | IARU Region 3 |
| Norway | 144.800 MHz | IARU Region 1 |
| Panama | 144.930 MHz | IARU Region 2 |
| Paraguay | 144.930 MHz | IARU Region 2 |
| Poland | 144.800 MHz | IARU Region 1 |
| Portugal | 144.800 MHz | IARU Region 1 |
| Russia | 144.800 MHz | IARU Region 1 |
| Singapore | 144.390 MHz | IARU Region 3 |
| South Africa | 144.800 MHz | IARU Region 1 |
| South Korea | 144.620 MHz | IARU Region 3 |
| Spain | 144.800 MHz | IARU Region 1 |
| Sweden | 144.800 MHz | IARU Region 1 |
| Switzerland | 144.800 MHz | IARU Region 1 |
| Taiwan | 144.640 MHz | IARU Region 3 |
| Thailand | 144.390 MHz | 145.525 MHz is also reported in use |
| Turkey | 144.800 MHz | IARU Region 1 |
| United Kingdom | 144.800 MHz | IARU Region 1 |
| United States | 144.390 MHz | IARU Region 2 |
| Uruguay | 144.930 MHz | IARU Region 2 |

### Regional defaults

- **IARU Region 1:** 144.800 MHz is the common default for Europe, Africa, the Middle East, and the former Soviet Union.
- **IARU Region 2:** 144.390 MHz is the common default for the Americas.
- **IARU Region 3:** There is no single regional default. Check the national band plan, particularly in Asia and the Pacific.

## HF APRS

HF APRS uses different modem modes and sideband conventions from ordinary 2 m APRS. Exact allocations vary by country.

| Band / use | Dial frequency | Mode / notes |
| --- | ---: | --- |
| 30 m legacy convention | 10.151 MHz | LSB, 300-baud AFSK convention |
| 30 m modern convention | 10.1476 MHz | USB equivalent for the same HF APRS signal |
| 30 m RPR | 10.1473 MHz | USB, Robust Packet Radio |
| 40 m RPR | 7.0473 MHz | USB, mostly Europe |
| 20 m APRS/RPR | 14.103 MHz / 14.1033 MHz | LSB APRS / USB RPR references |

Do not use the 10.151 MHz frequency as USB; the resulting signal would fall outside the 30 m amateur band.

## LoRa APRS

| Location | Frequency | Notes |
| --- | ---: | --- |
| Europe and common worldwide use | 433.775 MHz | Typical LoRa APRS channel; BW 125 kHz, SF12, CR 4:5 |
| United Kingdom | 439.9125 MHz | Alternative channel because of local band usage |
| North America | 433.775 MHz | Common, although some local groups use 902-928 MHz |

LoRa APRS is separate from conventional 1200-baud VHF APRS and requires compatible LoRa hardware and local frequency settings.

## Satellite and ISS APRS

| Service | Frequency | Notes |
| --- | ---: | --- |
| ISS APRS | 145.825 MHz | Traditional simplex APRS satellite channel; activity is intermittent |
| ISS APRS, current status | Check ARISS status | The active onboard radio and frequency can change |

Satellite operation requires checking the current satellite status, pass times, and applicable operating guidance before transmitting.

## Other Local or Historical Frequencies

- **144.8125 MHz:** Historical fallback reported for some European installations; 144.800 MHz is the current European default.
- **144.990 MHz:** Optional alternate input channel used by some North American digipeater systems; it is not a general APRS calling frequency.
- **145.780 MHz:** Older local report for Sao Paulo, Brazil. The broader current reference lists 145.570 MHz for Brazil, so verify locally.
- **433.800 MHz and 14.150 MHz:** Reported local activity in Sweden, not universal national defaults.

## APRS-IS

APRS-IS is the Internet-based APRS network and has no RF frequency. Frequency selection only applies when a station communicates through a radio, digipeater, iGate, HF link, LoRa iGate, or satellite.

## Sources

- [APRS Frequencies by Country - APRS World](https://aprs.world/guides/aprs-frequencies-by-country) - primary source for the country table, HF, and LoRa references; reviewed July 2026.
- [APRS Foundation](https://www.aprs.org/) - general APRS regional defaults and operating guidance.
- [APRS-IS](https://www.aprs-is.net/) - Internet-system background.
- [ARISS current ISS status](https://www.ariss.org/current-status-of-iss-stations.html) - current satellite operating status.
- [IARU Region 1](https://www.iaru-r1.org/) and [IARU Region 3](https://www.iaru-r3.org/) - regional band-plan authorities.

The national amateur-radio society and current band plan for the operating location take precedence over this document.
