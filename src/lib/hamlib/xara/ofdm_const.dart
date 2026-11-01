/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Shared OFDM constants.
*/

const int nfft = 1024;
const int ncp = 128;
const int nwin = 32;
const double fs = 48000.0;
const double binHz = fs / nfft;
const double symRatio = (nfft + ncp) / nfft;
