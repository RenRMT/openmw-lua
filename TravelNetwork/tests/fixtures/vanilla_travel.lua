-- GENERATED FILE -- do not edit.
--
-- Built from the game's own records by
-- TravelNetwork/sources/build_travel_fixture.py.
--
-- TEST DATA, not mod data. The mod reads destinations from NPC records
-- and operator positions from cells at runtime; this stands in for both
-- when the suite runs headless. Nothing under a mod directory reads it.
--
-- Positions are game units, rotations radians (esmtool prints degrees;
-- the Lua API returns radians, so the conversion happens here). A
-- destination or placement with no `cell` is in the exterior worldspace,
-- which is what the ESM says and all it says -- `exteriorNames` maps the
-- grid coordinates of the named exterior cells to their names.
--
-- Sorted by record id, so a regeneration that changes nothing produces
-- no diff. Placements keep the order the cells gave them.

return {
    operators = {
        {
            id = 'Adondasi Sadalvel',
            name = 'Adondasi Sadalvel',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec',
                    position = { 32319.0000, -72129.9000, 927.3750 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                    isInterior = false,
                    grid = { 3, -9 },
                },
            },
            destinations = {
                {
                    position = { -8681.2700, -70133.8050, 918.2370 },
                    rotation = { 0.0000, 0.0000, 0.3854 },
                },
                {
                    position = { 53161.1600, -48229.4770, 984.1380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 103448.5230, -58400.9100, 1547.8690 },
                    rotation = { 0.0000, 0.0000, 1.2000 },
                },
                {
                    position = { -21318.5120, -18232.8500, 1180.8390 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'ano andaram',
            name = 'Ano Andaram',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Foreign Quarter',
                    position = { 35692.9000, -74335.9000, 101.2040 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                    isInterior = false,
                    grid = { 4, -10 },
                },
            },
            destinations = {
                {
                    position = { -48489.7030, -39754.9300, 181.7120 },
                    rotation = { 0.0000, 0.0000, 1.3708 },
                },
                {
                    position = { 20377.6660, -102406.2340, 187.5220 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { 113965.0080, -61251.9260, 766.6770 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 119149.9220, -102117.0470, 158.7640 },
                    rotation = { 0.0000, 0.0000, 2.7854 },
                },
            },
        },
        {
            id = 'aren maren',
            name = 'Aren Maren',
            class = 'Gondolier',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Hlaalu',
                    position = { 23928.8000, -87537.9000, 579.8520 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = false,
                    grid = { 2, -11 },
                },
            },
            destinations = {
                {
                    position = { 33022.4610, -88001.4450, 132.4420 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 28829.2680, -76725.4920, 157.2530 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 30127.5680, -98356.5550, 172.5380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'baleni salavel',
            name = 'Baleni Salavel',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Hla Oad',
                    position = { -48637.0000, -39657.7000, 111.8850 },
                    rotation = { 0.0000, 0.0000, 1.2146 },
                    isInterior = false,
                    grid = { -6, -5 },
                },
            },
            destinations = {
                {
                    position = { 20380.2970, -102414.1480, 183.5130 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -58674.8160, 26485.3550, 185.7720 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 35748.9960, -74467.4920, 189.1070 },
                    rotation = { 0.0000, 0.0000, 4.2832 },
                },
                {
                    position = { 113960.1560, -61257.7110, 761.3100 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
            },
        },
        {
            id = 'basks_in_the_sun',
            name = 'Basks-In-The-Sun',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Fort Frostmoth',
                    position = { -174334.0000, 136861.0000, 320.5100 },
                    rotation = { 0.0000, 0.0000, 2.6000 },
                    isInterior = false,
                    grid = { -22, 16 },
                },
            },
            destinations = {
                {
                    position = { -69200.7270, 142117.5620, 214.0790 },
                    rotation = { 0.0000, 0.0000, 3.0832 },
                },
                {
                    position = { -199408.5620, 157218.9060, 435.1310 },
                    rotation = { 0.0000, 0.0000, 5.7664 },
                },
            },
        },
        {
            id = 'Blatta Hateria',
            name = 'Blatta Hateria',
            class = 'Pauper',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Ebonheart',
                    position = { 20570.1000, -101315.0000, 86.3068 },
                    rotation = { 0.0000, 0.0000, 3.9270 },
                    isInterior = false,
                    grid = { 2, -13 },
                },
            },
            destinations = {
                {
                    position = { 160255.0940, -36135.1640, 168.1050 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'dalse adren',
            name = 'Dalse Adren',
            class = 'Gondolier',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Arena',
                    position = { 33428.5000, -89213.4000, 589.5780 },
                    rotation = { 0.0000, 0.0000, 1.6708 },
                    isInterior = false,
                    grid = { 4, -11 },
                },
            },
            destinations = {
                {
                    position = { 30125.9510, -98355.6170, 173.4500 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 42593.8120, -87905.5230, 144.3360 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { 28828.9430, -76727.0080, 154.3250 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 22613.0680, -87935.8590, 105.2570 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'daras aryon',
            name = 'Daras Aryon',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Maar Gan',
                    position = { -22301.5000, 100047.0000, 2417.7800 },
                    rotation = { 0.0000, 0.0000, 6.1832 },
                    isInterior = false,
                    grid = { -3, 12 },
                },
            },
            destinations = {
                {
                    position = { -17642.2270, 54701.2190, 2863.6860 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { -65882.9060, 135516.0780, 1111.1690 },
                    rotation = { 0.0000, 0.0000, 1.3708 },
                },
                {
                    position = { -86779.1330, 89453.3440, 1126.5560 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'darvame hleran',
            name = 'Darvame Hleran',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Seyda Neen',
                    position = { -8604.4100, -70205.1000, 831.3380 },
                    rotation = { 0.0000, 0.0000, 0.2000 },
                    isInterior = false,
                    grid = { -2, -9 },
                },
            },
            destinations = {
                {
                    position = { -21318.7320, -18232.4060, 1177.6640 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { 32207.2150, -72223.8050, 1006.4370 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 53158.7930, -48228.8280, 984.1380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { -86786.0940, 89452.0700, 1130.6610 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'Daynas Darys',
            name = 'Daynas Darys',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    position = { 123182.0000, 40787.1000, 77.3454 },
                    rotation = { 0.0000, 0.0000, 0.6000 },
                    isInterior = false,
                    grid = { 15, 4 },
                },
            },
            destinations = {
                {
                    position = { 100663.2190, 114038.5080, 254.0900 },
                    rotation = { 0.0000, 0.0000, 3.8832 },
                },
                {
                    position = { 106924.6800, 117168.7580, 263.7040 },
                    rotation = { 0.0000, 0.0000, 0.6000 },
                },
                {
                    position = { 62677.7970, 184289.7660, 186.2370 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'devas irano',
            name = 'Devas Irano',
            class = 'Gondolier',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Foreign Quarter',
                    position = { 27537.2000, -77110.9000, 580.8170 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                    isInterior = false,
                    grid = { 3, -10 },
                },
            },
            destinations = {
                {
                    position = { 33020.7110, -87971.4450, 126.4240 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 22611.4650, -87935.9220, 107.3760 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { 42594.2270, -87906.0780, 145.7480 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'dilami androm',
            name = 'Dilami Androm',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Molag Mar',
                    position = { 103459.0000, -58515.4000, 1452.1200 },
                    rotation = { 0.0000, 0.0000, 0.8000 },
                    isInterior = false,
                    grid = { 12, -8 },
                },
            },
            destinations = {
                {
                    position = { 53162.0000, -48230.2500, 984.1380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 32207.0080, -72224.5860, 1007.1210 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
            },
        },
        {
            id = 'emelia duronia',
            name = 'Emelia Duronia',
            class = 'Guild Guide',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Caldera, Guild of Mages',
                    position = { 430.9910, 227.7040, 400.8530 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'Balmora, Guild of Mages',
                    position = { -754.6630, -1006.1610, -640.2350 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Ald-ruhn, Guild of Mages',
                    position = { 2594.1880, -509.6890, -267.5860 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    cell = 'Sadrith Mora, Wolverine Hall: Mage\'s Guild',
                    position = { -31.4100, 212.6810, 159.8490 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Vivec, Guild of Mages',
                    position = { 0.1790, 1392.8220, -385.9290 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'erranil',
            name = 'Erranil',
            class = 'Guild Guide',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Ald-ruhn, Guild of Mages',
                    position = { 2629.2000, -699.8380, -381.5790 },
                    rotation = { 0.0000, 0.0000, 6.2832 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'Balmora, Guild of Mages',
                    position = { -755.8970, -1002.7330, -644.6280 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Vivec, Guild of Mages',
                    position = { 3.5650, 1393.2600, -390.2000 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    cell = 'Sadrith Mora, Wolverine Hall: Mage\'s Guild',
                    position = { -30.2800, 212.1420, 158.2380 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Caldera, Guild of Mages',
                    position = { 521.4370, 335.1600, 489.7710 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'fendryn drelvi',
            name = 'Fendryn Delvi',
            class = 'Gondolier',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Telvanni',
                    position = { 43870.0000, -87539.5000, 594.0440 },
                    rotation = { 0.0000, 0.0000, 6.1832 },
                    isInterior = false,
                    grid = { 5, -11 },
                },
            },
            destinations = {
                {
                    position = { 33018.1760, -87911.8590, 143.1450 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 28829.5060, -76725.1640, 157.1960 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 30125.8710, -98353.5620, 174.6780 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'flacassia fauseius',
            name = 'Flacassia Fauseius',
            class = 'Guild Guide',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Guild of Mages',
                    position = { 96.9000, 1432.6500, -478.7450 },
                    rotation = { 0.0000, 0.0000, 3.9270 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'Ald-ruhn, Guild of Mages',
                    position = { 2597.3200, -509.3650, -264.2760 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    cell = 'Balmora, Guild of Mages',
                    position = { -755.8970, -1002.7330, -644.6280 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Sadrith Mora, Wolverine Hall: Mage\'s Guild',
                    position = { -30.2800, 212.1420, 158.2380 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Caldera, Guild of Mages',
                    position = { 523.1630, 335.7270, 487.8720 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'folsi thendas',
            name = 'Folsi Thendas',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Suran',
                    position = { 53155.8000, -47745.8000, 1116.5600 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                    isInterior = false,
                    grid = { 6, -6 },
                },
            },
            destinations = {
                {
                    position = { -21322.6970, -18234.5430, 1183.2420 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -8680.6010, -70135.7890, 919.5940 },
                    rotation = { 0.0000, 0.0000, 0.3854 },
                },
                {
                    position = { 32206.3770, -72225.1170, 1006.6580 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 103449.0160, -58402.7890, 1545.5380 },
                    rotation = { 0.0000, 0.0000, 1.2000 },
                },
            },
        },
        {
            id = 'gals arethi',
            name = 'Gals Arethi',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Sadrith Mora',
                    position = { 142120.0000, 39365.6000, 278.4590 },
                    rotation = { 0.0000, 0.0000, 5.1000 },
                    isInterior = false,
                    grid = { 17, 4 },
                },
            },
            destinations = {
                {
                    position = { 119153.3980, -102116.1720, 159.7930 },
                    rotation = { 0.0000, 0.0000, 2.7832 },
                },
                {
                    position = { 20362.7870, -102424.5000, 185.2710 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { 106927.8750, 117172.4140, 262.7750 },
                    rotation = { 0.0000, 0.0000, 0.6000 },
                },
                {
                    position = { 62681.5080, 184288.6410, 188.3980 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'haema farseer',
            name = 'Haema Farseer',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Dagon Fel',
                    position = { 62333.0000, 184190.0000, 85.9486 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                    isInterior = false,
                    grid = { 7, 22 },
                },
            },
            destinations = {
                {
                    position = { 106921.3590, 117169.1250, 263.3590 },
                    rotation = { 0.0000, 0.0000, 0.6000 },
                },
                {
                    position = { 141870.9060, 38621.2420, 331.3380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { -69427.6720, 142115.7500, 192.2500 },
                    rotation = { 0.0000, 0.0000, 3.0416 },
                },
                {
                    position = { 123303.9060, 41164.4610, 182.4730 },
                    rotation = { 0.0000, 0.0000, 0.9000 },
                },
            },
        },
        {
            id = 'iniel',
            name = 'Iniel',
            class = 'Guild Guide',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Sadrith Mora, Wolverine Hall: Mage\'s Guild',
                    position = { -70.1345, 434.5220, 65.9905 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'Ald-ruhn, Guild of Mages',
                    position = { 2592.8890, -511.8540, -261.0500 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    cell = 'Balmora, Guild of Mages',
                    position = { -755.8970, -1002.7330, -644.6280 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Vivec, Guild of Mages',
                    position = { 3.5200, 1391.3250, -385.8530 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    cell = 'Caldera, Guild of Mages',
                    position = { 525.7140, 334.8050, 490.1270 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'masalinie merian',
            name = 'Masalinie Merian',
            class = 'Guild Guide',
            recordType = 'NPC',
            services = 0x00000800,
            placements = {
                {
                    cell = 'Balmora, Guild of Mages',
                    position = { -627.9320, -1079.8200, -753.7770 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'Ald-ruhn, Guild of Mages',
                    position = { 2597.4670, -511.1540, -265.3280 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    cell = 'Vivec, Guild of Mages',
                    position = { 4.5620, 1393.7880, -388.1090 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    cell = 'Sadrith Mora, Wolverine Hall: Mage\'s Guild',
                    position = { -30.2800, 212.1420, 158.2380 },
                    rotation = { 0.0000, 0.0000, 0.7854 },
                },
                {
                    cell = 'Caldera, Guild of Mages',
                    position = { 519.8270, 334.8420, 489.2090 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'navam veran',
            name = 'Navam Veran',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Ald-ruhn',
                    position = { -17654.6000, 54770.1000, 2774.6600 },
                    rotation = { 0.0000, 0.0000, 2.2000 },
                    isInterior = false,
                    grid = { -3, 6 },
                },
            },
            destinations = {
                {
                    position = { -21320.6740, -18233.1130, 1179.0320 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -65872.7190, 135522.2660, 1101.9830 },
                    rotation = { 0.0000, 0.0000, 1.4000 },
                },
                {
                    position = { -22371.0160, 100115.5860, 2519.3960 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -86782.3670, 89454.3520, 1124.3340 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'Nevosi Hlan',
            name = 'Nevosi Hlan',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Ebonheart',
                    position = { 20233.0000, -103320.0000, 160.4660 },
                    rotation = { 0.0000, 0.0000, 5.9978 },
                    isInterior = false,
                    grid = { 2, -13 },
                },
            },
            destinations = {
                {
                    position = { 35751.1090, -74468.7340, 189.0210 },
                    rotation = { 0.0000, 0.0000, 4.2832 },
                },
                {
                    position = { -48493.7270, -39754.0430, 187.7850 },
                    rotation = { 0.0000, 0.0000, 1.4000 },
                },
                {
                    position = { 119148.2580, -102117.8360, 151.4850 },
                    rotation = { 0.0000, 0.0000, 2.8416 },
                },
                {
                    position = { 141877.8590, 38637.3090, 337.9690 },
                    rotation = { 0.0000, 0.0000, 3.0832 },
                },
            },
        },
        {
            id = 'nireli farys',
            name = 'Nireli Farys',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Tel Branora',
                    position = { 119243.0000, -102108.0000, 57.5427 },
                    rotation = { 0.0000, 0.0000, 3.3832 },
                    isInterior = false,
                    grid = { 14, -13 },
                },
            },
            destinations = {
                {
                    position = { 35750.6480, -74467.5620, 190.8720 },
                    rotation = { 0.0000, 0.0000, 4.2832 },
                },
                {
                    position = { 113948.6020, -61251.4530, 755.2900 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 141880.2190, 38646.4450, 315.2940 },
                    rotation = { 0.0000, 0.0000, 3.0832 },
                },
                {
                    position = { 20361.3440, -102425.2580, 182.3510 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'punibi yahaz',
            name = 'Punibi Yahaz',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Gnisis',
                    position = { -86648.4000, 89353.0000, 1043.4300 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = false,
                    grid = { -11, 10 },
                },
            },
            destinations = {
                {
                    position = { -17641.5140, 54701.1760, 2863.4530 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { -22369.4320, 100114.1090, 2523.5870 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -65875.5940, 135522.3440, 1106.4600 },
                    rotation = { 0.0000, 0.0000, 1.4000 },
                },
                {
                    position = { -8680.8720, -70138.6560, 923.2980 },
                    rotation = { 0.0000, 0.0000, 0.4000 },
                },
            },
        },
        {
            id = 'rindral dralor',
            name = 'Rindral Dralor',
            class = 'Rogue',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Molag Mar',
                    position = { 113845.0000, -61405.8000, 585.5640 },
                    rotation = { 0.0000, 0.0000, 4.0832 },
                    isInterior = false,
                    grid = { 13, -8 },
                },
            },
            destinations = {
                {
                    position = { 35752.4410, -74468.7110, 190.2720 },
                    rotation = { 0.0000, 0.0000, 4.3124 },
                },
                {
                    position = { -48492.6680, -39754.5230, 187.1250 },
                    rotation = { 0.0000, 0.0000, 1.4000 },
                },
                {
                    position = { 119153.2110, -102118.2660, 155.0230 },
                    rotation = { 0.0000, 0.0000, 2.7832 },
                },
            },
        },
        {
            id = 's\'virr',
            name = 'S\'virr',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Khuul',
                    position = { -68964.4000, 142156.0000, 120.0230 },
                    rotation = { 0.0000, 0.0000, 4.3832 },
                    isInterior = false,
                    grid = { -9, 17 },
                },
            },
            destinations = {
                {
                    position = { -174024.3910, 136823.9530, 457.6680 },
                    rotation = { 0.0000, 0.0000, 4.6832 },
                },
            },
        },
        {
            id = 'sedyni veran',
            name = 'Sedyni Veran',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vos',
                    position = { 100771.0000, 114190.0000, 136.8900 },
                    rotation = { 0.0000, 0.0000, 3.6270 },
                    isInterior = false,
                    grid = { 12, 13 },
                },
            },
            destinations = {
                {
                    position = { 141876.9530, 38613.1210, 325.0060 },
                    rotation = { 0.0000, 0.0000, 3.1004 },
                },
                {
                    position = { 123303.8980, 41163.8980, 180.3560 },
                    rotation = { 0.0000, 0.0000, 0.9000 },
                },
                {
                    position = { 106924.5550, 117169.2970, 263.7070 },
                    rotation = { 0.0000, 0.0000, 0.6000 },
                },
            },
        },
        {
            id = 'seldus nerendus',
            name = 'Seldus Nerendus',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Khuul',
                    position = { -65939.2000, 135592.0000, 974.8910 },
                    rotation = { 0.0000, 0.0000, 1.3000 },
                    isInterior = false,
                    grid = { -9, 16 },
                },
            },
            destinations = {
                {
                    position = { -22370.8520, 100115.1410, 2520.1320 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
                {
                    position = { -17640.6190, 54698.7580, 2866.8610 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { -86780.3280, 89454.1560, 1125.2220 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                },
            },
        },
        {
            id = 'selvil sareloth',
            name = 'Selvil Sareloth',
            class = 'Caravaner',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Balmora',
                    position = { -21226.6000, -18292.2000, 1097.3400 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = false,
                    grid = { -3, -3 },
                },
            },
            destinations = {
                {
                    position = { -17642.6430, 54699.1480, 2865.9160 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { -8681.4280, -70136.1020, 919.9390 },
                    rotation = { 0.0000, 0.0000, 0.4000 },
                },
                {
                    position = { 53159.5510, -48228.6050, 984.1380 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 32206.8850, -72222.4220, 1004.6460 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
            },
        },
        {
            id = 'talmeni drethan',
            name = 'Talmeni Drethan',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Khuul',
                    position = { -69561.2000, 142138.0000, 94.0168 },
                    rotation = { 0.0000, 0.0000, 2.3562 },
                    isInterior = false,
                    grid = { -9, 17 },
                },
            },
            destinations = {
                {
                    position = { -58679.2110, 26485.9390, 190.1120 },
                    rotation = { 0.0000, 0.0000, 4.7124 },
                },
                {
                    position = { 62679.1600, 184288.8750, 185.8400 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'talsi uvayn',
            name = 'Talsi Uvayn',
            class = 'Gondolier',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Vivec, Temple',
                    position = { 30770.7000, -99639.2000, 589.8270 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                    isInterior = false,
                    grid = { 3, -13 },
                },
            },
            destinations = {
                {
                    position = { 33040.2150, -87932.1330, 109.7060 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 22611.7850, -87934.0310, 98.4150 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
                {
                    position = { 42593.9880, -87906.4920, 146.8850 },
                    rotation = { 0.0000, 0.0000, 1.5708 },
                },
            },
        },
        {
            id = 'todd',
            name = 'Todd\'s Super Tester Guy',
            class = 'Guard',
            recordType = 'NPC',
            services = 0x0003FFFF,
            placements = {
                {
                    cell = 'ToddTest',
                    position = { 1657.6500, 261.2940, -642.2870 },
                    rotation = { 0.0000, 0.0000, 2.6180 },
                    isInterior = true,
                },
            },
            destinations = {
                {
                    cell = 'ToddTest',
                    position = { 1822.6410, -231.5320, -292.9500 },
                    rotation = { 0.0000, 0.0000, 0.5000 },
                },
            },
        },
        {
            id = 'tonas telvani',
            name = 'Tonas Telvani',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Tel Mora',
                    position = { 107070.0000, 117142.0000, 191.6840 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = false,
                    grid = { 13, 14 },
                },
            },
            destinations = {
                {
                    position = { 141874.3120, 38605.5980, 326.8210 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 62677.7420, 184290.2500, 186.3460 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
                {
                    position = { 100663.6410, 114037.3050, 255.4710 },
                    rotation = { 0.0000, 0.0000, 3.8832 },
                },
                {
                    position = { 123304.7190, 41165.2190, 178.3970 },
                    rotation = { 0.0000, 0.0000, 0.9000 },
                },
            },
        },
        {
            id = 'valveli arelas',
            name = 'Valveli Arelas',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Gnaar Mok',
                    position = { -58163.0000, 26616.5000, 18.8225 },
                    rotation = { 0.0000, 0.0000, 3.9270 },
                    isInterior = false,
                    grid = { -8, 3 },
                },
            },
            destinations = {
                {
                    position = { -69428.7890, 142115.7190, 195.1440 },
                    rotation = { 0.0000, 0.0000, 3.0416 },
                },
                {
                    position = { -48492.9690, -39756.7930, 187.1810 },
                    rotation = { 0.0000, 0.0000, 1.3708 },
                },
            },
        },
        {
            id = 'veresa alver',
            name = 'Veresa Alver',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
                {
                    cell = 'Raven Rock',
                    position = { -199432.0000, 157049.0000, 237.6620 },
                    rotation = { 0.0000, 0.0000, 0.0000 },
                    isInterior = false,
                    grid = { -25, 19 },
                },
            },
            destinations = {
                {
                    position = { -174016.0000, 136704.0000, 448.0000 },
                    rotation = { 0.0000, 0.0000, 4.7000 },
                },
            },
        },
        {
            id = 'vevrana aryon',
            name = 'Vevrana Aryon',
            class = 'Monk',
            recordType = 'NPC',
            services = 0x00A00000,
            placements = {
                {
                    position = { 160323.0000, -35965.5000, 99.3328 },
                    rotation = { 0.0000, 0.0000, 3.6832 },
                    isInterior = false,
                    grid = { 19, -5 },
                },
            },
            destinations = {
                {
                    position = { 20426.1130, -101409.0700, 162.6860 },
                    rotation = { 0.0000, 0.0000, 3.1416 },
                },
            },
        },
        {
            id = 'wind_in_his_hair',
            name = 'Wind-In-His-Hair',
            class = 'Shipmaster',
            recordType = 'NPC',
            services = 0x00000000,
            placements = {
            },
            destinations = {
                {
                    position = { -69200.7270, 142117.5620, 214.0790 },
                    rotation = { 0.0000, 0.0000, 3.0832 },
                },
            },
        },
    },
    exteriorNames = {
        ['-27,22'] = 'Solstheim, Thormoor\'s Watch',
        ['-26,26'] = 'Solstheim, Mortrag Glacier',
        ['-26,27'] = 'Solstheim, Mortrag Glacier',
        ['-25,19'] = 'Raven Rock',
        ['-25,23'] = 'Solstheim, Hvitkald Peak',
        ['-25,26'] = 'Solstheim, Mortrag Glacier',
        ['-25,27'] = 'Solstheim, Mortrag Glacier',
        ['-24,19'] = 'Raven Rock',
        ['-24,25'] = 'Solstheim, Hrothmund\'s Bane',
        ['-24,26'] = 'Solstheim, Castle Karstaag',
        ['-23,20'] = 'Solstheim, Brodir Grove',
        ['-23,23'] = 'Solstheim, Altar of Thrond',
        ['-22,16'] = 'Fort Frostmoth',
        ['-22,17'] = 'Fort Frostmoth',
        ['-21,23'] = 'Solstheim, Lake Fjalding',
        ['-20,23'] = 'Solstheim, Lake Fjalding',
        ['-20,25'] = 'Skaal Village',
        ['-20,26'] = 'Skaal Village',
        ['-19,23'] = 'Thirsk',
        ['-17,24'] = 'Solstheim, Gyldenhul Barrow Entrance',
        ['-11,9'] = 'Koal Cave Entrance',
        ['-11,10'] = 'Gnisis',
        ['-11,11'] = 'Gnisis',
        ['-11,15'] = 'Ald Velothi',
        ['-10,9'] = 'Berandas',
        ['-10,11'] = 'Gnisis',
        ['-10,15'] = 'Ashalmawia',
        ['-9,4'] = 'Khartag Point',
        ['-9,5'] = 'Andasreth',
        ['-9,16'] = 'Khuul',
        ['-9,17'] = 'Khuul',
        ['-8,3'] = 'Gnaar Mok',
        ['-7,-4'] = 'Ashurnibibi',
        ['-6,-5'] = 'Hla Oad',
        ['-6,-1'] = 'Hlormaren',
        ['-5,-5'] = 'Odai Plateau',
        ['-5,9'] = 'Bal Isra',
        ['-5,18'] = 'Ashurnabitashpi',
        ['-4,-2'] = 'Balmora',
        ['-4,18'] = 'Urshilaku Camp',
        ['-4,21'] = 'Ald Redaynia',
        ['-3,-3'] = 'Balmora',
        ['-3,-2'] = 'Balmora',
        ['-3,6'] = 'Ald-ruhn',
        ['-3,12'] = 'Maar Gan',
        ['-2,-10'] = 'Seyda Neen',
        ['-2,-9'] = 'Seyda Neen',
        ['-2,-2'] = 'Balmora',
        ['-2,2'] = 'Caldera',
        ['-2,5'] = 'Buckmoth Legion Fort',
        ['-2,6'] = 'Ald-ruhn',
        ['-2,7'] = 'Ald-ruhn',
        ['-2,15'] = 'Falasmaryon',
        ['-1,-3'] = 'Moonmoth Legion Fort',
        ['-1,18'] = 'Valenvaryon',
        ['0,-8'] = 'Pelagiad',
        ['0,-7'] = 'Pelagiad',
        ['0,10'] = 'Vemynal',
        ['0,14'] = 'Kogoruhn',
        ['0,22'] = 'Vas',
        ['1,-13'] = 'Ebonheart',
        ['1,-5'] = 'Fields of Kummu',
        ['1,21'] = 'Sanctus Shrine',
        ['2,-13'] = 'Ebonheart',
        ['2,-11'] = 'Vivec, Hlaalu',
        ['2,-10'] = 'Vivec',
        ['2,-7'] = 'Dren Plantation',
        ['2,-6'] = 'Arvel Plantation',
        ['2,4'] = 'Ghostgate',
        ['2,8'] = 'Dagoth Ur',
        ['3,-14'] = 'Vivec, Temple',
        ['3,-13'] = 'Vivec, Temple',
        ['3,-12'] = 'Vivec, St. Delyn',
        ['3,-11'] = 'Vivec, Redoran',
        ['3,-10'] = 'Vivec, Foreign Quarter',
        ['3,-9'] = 'Vivec',
        ['3,7'] = 'Odrosal',
        ['4,-14'] = 'Vivec, Temple',
        ['4,-13'] = 'Vivec, Temple',
        ['4,-12'] = 'Vivec, St. Olms',
        ['4,-11'] = 'Vivec, Arena',
        ['4,-10'] = 'Vivec, Foreign Quarter',
        ['4,-3'] = 'Marandus',
        ['4,9'] = 'Tureynulal',
        ['5,-11'] = 'Vivec, Telvanni',
        ['5,-10'] = 'Vivec',
        ['5,15'] = 'Zergonipal',
        ['6,-9'] = 'Ald Sotha',
        ['6,-7'] = 'Suran',
        ['6,-6'] = 'Suran',
        ['6,-5'] = 'Bal Ur',
        ['6,18'] = 'Rotheran',
        ['6,21'] = 'Mzuleft Ruin',
        ['7,22'] = 'Dagon Fel',
        ['8,-12'] = 'Bal Fell',
        ['8,-10'] = 'Mzahnch Ruin',
        ['8,12'] = 'Nchuleft Ruin',
        ['9,-12'] = 'Bal Fell',
        ['9,-7'] = 'Telasero',
        ['9,6'] = 'Falensarano',
        ['9,10'] = 'Zainab Camp',
        ['10,-3'] = 'Nchuleftingth',
        ['10,1'] = 'Uvirith\'s Grave',
        ['10,14'] = 'Tel Vos',
        ['11,-5'] = 'Mount Kand',
        ['11,14'] = 'Vos',
        ['11,16'] = 'Ahemmusa Camp',
        ['11,20'] = 'Ald Daedroth',
        ['12,-10'] = 'Zaintiraris',
        ['12,-8'] = 'Molag Mar',
        ['12,4'] = 'Yansirramus',
        ['12,13'] = 'Vos',
        ['13,-8'] = 'Molag Mar',
        ['13,-1'] = 'Erabenimsun Camp',
        ['13,14'] = 'Tel Mora',
        ['14,-13'] = 'Tel Branora',
        ['14,-4'] = 'Mount Assarnibibi',
        ['15,-13'] = 'Tel Branora',
        ['15,1'] = 'Tel Fyr',
        ['15,5'] = 'Tel Aruhn',
        ['17,-6'] = 'Nchurdamz',
        ['17,4'] = 'Sadrith Mora',
        ['17,5'] = 'Sadrith Mora',
        ['18,3'] = 'Wolverine Hall',
        ['18,4'] = 'Sadrith Mora',
        ['19,-4'] = 'Holamayan',
    },
}
