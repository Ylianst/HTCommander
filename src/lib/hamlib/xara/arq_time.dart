/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
ARQ time base: one tick is one 48 kHz audio sample.
*/

const int second = 48000;
const int idlePoll = 10 * second;
const int idlePollLimit = 7;
const int discTimeoutLimit = 3;
