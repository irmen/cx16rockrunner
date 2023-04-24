bd1caves {

    const ubyte NUM_CAVES = 20

    sub decode(ubyte level) {

        cave.rockford_state = 0
        cave.player_x = 0
        cave.player_y = 0
        cave.name_ptr = names[level]
        cave.description_ptr = descriptions[level]
        uword data_ptr = caves[level]
        cave.cave_number = data_ptr[$00]
        cave.intermission = cave.cave_number%5==0
        if cave.intermission {
            cave.width = 22
            cave.height = 12
        } else {
            cave.width = 40
            cave.height = 22
        }
        cave.magicwall_millingtime_sec = data_ptr[$01]
        cave.amoeba_slow_time_sec = data_ptr[$01]       ; shared with milling time
        cave.initial_diamond_value = data_ptr[$02]
        cave.extra_diamond_value = data_ptr[$03]
        seed1 = 0
        seed2 = data_ptr[$04]                   ; TODO difficulty level selectable (data $04-$08 for level 1-5)
        cave.diamonds_needed = data_ptr[$09]    ; TODO difficulty level selectable (data $09-$0d for level 1-5)
        cave.cave_time_sec = data_ptr[$0e]      ; TODO difficulty level selectable (data $0e-$12 for level 1-5)
        cave.color_background1 = data_ptr[$13]
        cave.color_background2 = data_ptr[$14]
        cave.color_foreground = data_ptr[$15]
        ; $16 and $17 are unused?
        ubyte rnd_object0 = translate_objects[data_ptr[$18]]
        ubyte rnd_object1 = translate_objects[data_ptr[$19]]
        ubyte rnd_object2 = translate_objects[data_ptr[$1a]]
        ubyte rnd_object3 = translate_objects[data_ptr[$1b]]
        ubyte rnd_attr0 = initial_attributes(data_ptr[$18])
        ubyte rnd_attr1 = initial_attributes(data_ptr[$19])
        ubyte rnd_attr2 = initial_attributes(data_ptr[$1a])
        ubyte rnd_attr3 = initial_attributes(data_ptr[$1b])
        ubyte rnd_probability0 = data_ptr[$1c]
        ubyte rnd_probability1 = data_ptr[$1d]
        ubyte rnd_probability2 = data_ptr[$1e]
        ubyte rnd_probability3 = data_ptr[$1f]

        ; first fill the cave via the random fill
        ubyte x
        ubyte y
        for y in 1 to cave.height-2 {
            for x in 0 to cave.width-1 {
                cx16.r0L = objects.dirt
                bdrandom()
                if seed1 < rnd_probability0 {
                    cx16.r0L = rnd_object0
                    cx16.r1L = rnd_attr0
                }
                if seed1 < rnd_probability1 {
                    cx16.r0L = rnd_object1
                    cx16.r1L = rnd_attr1
                }
                if seed1 < rnd_probability2 {
                    cx16.r0L = rnd_object2
                    cx16.r1L = rnd_attr2
                }
                if seed1 < rnd_probability3 {
                    cx16.r0L = rnd_object3
                    cx16.r1L = rnd_attr3
                }
                draw_single(cx16.r0L, cx16.r1L, x, y)
            }
        }
        draw_rectangle(objects.steel, 0, 0, 0, cave.width, cave.height, 0, 0)    ; the boundary

        data_ptr += $20
        while @(data_ptr) != $ff {
            ubyte obj = translate_objects[@(data_ptr) & $3f]
            ubyte attr = initial_attributes(@(data_ptr) & $3f)
            ubyte kind = (@(data_ptr) & $c0) >> 6
            x = data_ptr[1]
            y = data_ptr[2] - 2   ; apparently need to adjust for top 2 lines where score is shown on c64
            when kind {
                0 -> {
                    draw_single(obj, attr, x, y)
                    data_ptr += 3
                }
                1 -> {
                    draw_line(obj, attr, x, y, data_ptr[3], data_ptr[4])
                    data_ptr += 5
                }
                2 -> {
                    draw_rectangle(obj, attr, x, y, data_ptr[3], data_ptr[4], translate_objects[data_ptr[5]], initial_attributes(data_ptr[5]))
                    data_ptr += 6
                }
                3 -> {
                    draw_rectangle(obj, attr, x, y, data_ptr[3], data_ptr[4], 0, 0)
                    data_ptr += 5
                }
            }
        }
    }

    ubyte @shared seed1
    ubyte @shared seed2
    sub bdrandom() {
        ; the pseudo random generator that Boulderdash C64 used
        ; see https://www.elmerproductions.com/sp/peterb/insideBoulderdash.html#Random%20numbers
        ubyte @shared temp1
        ubyte @shared temp2
        %asm {{
            lda  seed1
            ror  a
            ror  a
            and  #$80
            sta  temp1
            lda  seed2
            ror  a
            and  #$7f
            sta  temp2
            lda  seed2
            ror  a
            ror  a
            and  #$80
            clc
            adc  seed2
            adc  #$13
            sta  seed2
            lda  seed1
            adc  temp1
            adc  temp2
            sta  seed1
        }}
    }

    sub draw_single(ubyte obj, ubyte attr, ubyte x, ubyte y) {
        cave.set_tile(x, y, obj, attr)
        if obj==objects.inboxclosed or obj==objects.rockfordbirth {
            cave.player_x = x
            cave.player_y = y
        }
    }

    sub draw_rectangle(ubyte obj, ubyte attr, ubyte x1, ubyte y1, ubyte width, ubyte height, ubyte fillobj, ubyte fillattr) {
        draw_line(obj, attr, x1, y1, width, 2)
        draw_line(obj, attr, x1, y1 + height - 1, width, 2)
        draw_line(obj, attr, x1, y1 + 1, height - 2, 4)
        draw_line(obj, attr, x1 + width - 1, y1 + 1, height - 2, 4)
        if fillobj {
            ubyte y
            for y in y1 + 1 to y1 + height - 2
                draw_line(fillobj, fillattr, x1 + 1, y, width - 2, 2)
        }
    }

    sub draw_line(ubyte obj, ubyte attr, ubyte x, ubyte y, ubyte length, ubyte direction) {
        ubyte[] deltax = [ 0, 1, 1, 1, 0,-1,-1,-1]
        ubyte[] deltay = [-1,-1, 0, 1, 1, 1, 0,-1]
        ubyte dx = deltax[direction]
        ubyte dy = deltay[direction]
        repeat length {
            draw_single(obj, attr, x, y)
            x+=dx
            y+=dy
        }
    }

    ubyte[64] translate_objects = [
        objects.space,          ; 00
        objects.dirt,           ; 01
        objects.wall,           ; 02
        objects.magicwallinactive, ; 03
        objects.outboxclosed,   ; 04
        objects.outboxblinking, ; 05
        objects.slime,          ; 06
        objects.steel,          ; 07
        objects.firefly,        ; 08
        objects.firefly,        ; 09
        objects.firefly,        ; 0a
        objects.firefly,        ; 0b
        0,                      ; 0c
        0,                      ; 0d
        0,                      ; 0e
        0,                      ; 0f
        objects.boulder,        ; 10
        0,                      ; 11
        objects.boulder,        ; 12
        0,                      ; 13
        objects.diamond,        ; 14
        0,                      ; 15
        objects.diamond,        ; 16
        0,                      ; 17
        0,                      ; 18
        0,                      ; 19
        0,                      ; 1a
        0,                      ; 1b
        0,                      ; 1c
        0,                      ; 1d
        0,                      ; 1e
        0,                      ; 1f
        0,                      ; 20
        0,                      ; 21
        0,                      ; 22
        0,                      ; 23
        0,                      ; 24
        objects.inboxclosed,    ; 25
        0,                      ; 26
        0,                      ; 27
        0,                      ; 28
        0,                      ; 29
        0,                      ; 2a
        0,                      ; 2b
        0,                      ; 2c
        0,                      ; 2d
        0,                      ; 2e
        0,                      ; 2f
        objects.butterfly,      ; 30
        objects.butterfly,      ; 31
        objects.butterfly,      ; 32
        objects.butterfly,      ; 33
        0,                      ; 34
        0,                      ; 35
        0,                      ; 36
        0,                      ; 37
        objects.rockfordbirth,  ; 38
        0,                      ; 39
        objects.amoeba,         ; 3a
        0,                      ; 3b
        0,                      ; 3c
        0,                      ; 3d
        objects.horizexpander,  ; 3e
        0                       ; 3f
    ]

    sub initial_attributes(ubyte id) -> ubyte {
        when id {
            $08, $31 -> return cave.ATTR_MOVING_LEFT
            $09, $32 -> return cave.ATTR_MOVING_UP
            $0a, $33 -> return cave.ATTR_MOVING_RIGHT
            $0b, $30 -> return cave.ATTR_MOVING_DOWN
            else -> return 0
        }
    }

    
    str[NUM_CAVES+1] names = [
        "",
        "A - Intro",
        "B - Rooms",
        "C - Maze",
        "D - Butterflies",
        "Intermission 1",
        "E - Guards",
        "F - Firefly dens",
        "G - Amoeba",
        "H - Enchanted wall",
        "Intermission 2",
        "I - Greed",
        "J - Tracks",
        "K - Crowd",
        "L - Walls",
        "Intermission 3",
        "M - Apocalypse",
        "N - Zigzag",
        "O - Funnel",
        "P - Enchanted boxes",
        "Intermission 4"
    ]

    str[NUM_CAVES+1] descriptions = [
        ; Cave 0 - not selectable (level starts at 1)
        "",
        ; Cave A
        "Pick up jewels and exit|before time is up.",
        ; Cave B
        "Pick up jewels, but you must|move boulders to get all jewels.",
        ; Cave C
        "Pick up jewels.|You must get every jewel to exit.",
        ; Cave D
        "Drop boulders on butterflies|to create jewels.",
        ; Intermission 1
        "Bonus level!",
        ; Cave E
        "The jewels are there for grabbing,|but they are guarded|by the deadly fireflies.",
        ; Cave F
        "Each firefly is guarding a jewel.",
        ; Cave G
        "Surround the amoeba with boulders.|Pick up jewels when it suffocates.",
        ; Cave H
        "Activate the enchanted wall and|create as many jewels as you can.",
        ; Intermission 2
        "Bonus level!",
        ; Cave I
        "You have to get a lot of jewels|here, lucky there are so many.",
        ; Cave J
        "Get the jewels, avoid the fireflies.",
        ; Cave K
        "You must move a lot of boulders|around in some tight spaces.",
        ; Cave L
        "Drop a boulder on a firefly|at the right time|to blast through walls.",
        ; Intermission 3
        "Bonus level!",
        ; Cave M
        "Bring the butterflies and amoeba|together and watch the jewels fly.",
        ; Cave N
        "Magically transform the butterflies|into jewels, but don't waste|any boulders.",
        ; Cave O
        "There is an enchanted wall at|the bottom of the rock tunnel.",
        ; Cave P
        "The top of each room is an|enchanted wall, but you'll|have to blast your way inside.",
        ; Intermission 4
        "Bonus level!"
    ]

    uword[NUM_CAVES+1] caves = [
        0,
        &caveA,
        &caveB,
        &caveC,
        &caveD,
        &intermission1,
        &caveE,
        &caveF,
        &caveG,
        &caveH,
        &intermission2,
        &caveI,
        &caveJ,
        &caveK,
        &caveL,
        &intermission3,
        &caveM,
        &caveN,
        &caveO,
        &caveP,
        &intermission4
    ]

    ubyte[] caveA = [$01, $14, $0A, $0F, $0A, $0B, $0C, $0D, $0E, $0C, $0C, $0C, $0C, $0C, $96, $6E,
                     $46, $28, $1E, $08, $0B, $09, $D4, $20, $00, $10, $14, $00, $3C, $32, $09, $00,
                     $42, $01, $09, $1E, $02, $42, $09, $10, $1E, $02, $25, $03,
                     $04, $04, $26, $12, $FF]
    ubyte[] caveB = [$02, $14, $14, $32, $03, $00, $01, $57, $58, $0A, $0C, $09, $0D, $0A, $96, $6E,
                     $46, $46, $46, $0A, $04, $09, $00, $00, $00, $10, $14, $08, $3C, $32, $09, $02,
                     $42, $01, $08, $26, $02, $42, $01, $0F, $26, $02, $42, $08,
                     $03, $14, $04, $42, $10, $03, $14, $04, $42, $18, $03, $14, $04, $42, $20, $03, $14, $04, $40, $01, $05, $26,
                     $02, $40, $01, $0B, $26, $02, $40, $01, $12, $26, $02, $40, $14, $03, $14, $04, $25, $12, $15, $04, $12, $16,
                     $FF]
    ubyte[] caveC = [$03, $00, $0F, $00, $00, $32, $36, $34, $37, $18, $17, $18, $17, $15, $96, $64,
                     $5A, $50, $46, $09, $08, $09, $04, $00, $02, $10, $14, $00, $64, $32, $09, $00,
                     $25, $03, $04, $04, $27, $14, $FF]
    ubyte[] caveD = [$04, $14, $05, $14, $00, $6E, $70, $73, $77, $24, $24, $24, $24, $24, $78, $64,
                     $50, $3C, $32, $04, $08, $09, $00, $00, $10, $00, $00, $00, $14, $00, $00, $00,
                     $25, $01, $03, $04, $26, $16, $81, $08, $0A, $04, $04, $00,
                     $30, $0A, $0B, $81, $10, $0A, $04, $04, $00, $30, $12, $0B, $81, $18, $0A, $04, $04, $00, $30, $1A, $0B, $81,
                     $20, $0A, $04, $04, $00, $30, $22, $0B, $FF]
    ubyte[] intermission1 = [
                     $11, $14, $1E, $00, $0A, $0B, $0C, $0D, $0E, $06, $06, $06, $06, $06, $0A, $0A,
                     $0A, $0A, $0A, $0E, $02, $09, $00, $00, $00, $14, $00, $00, $FF, $09, $00, $00,
                     $87, $00, $02, $28, $16, $07, $87, $00, $02, $14, $0C, $00,
                     $32, $0A, $0C, $10, $0A, $04, $01, $0A, $05, $25, $03, $05, $04, $12, $0C, $FF]
    ubyte[] caveE = [$05, $14, $32, $5A, $00, $00, $00, $00, $00, $04, $05, $06, $07, $08, $96, $78,
                     $5A, $3C, $1E, $09, $0A, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
                     $25, $01, $03, $04, $27, $16, $80, $08, $0A, $03, $03, $00,
                     $80, $10, $0A, $03, $03, $00, $80, $18, $0A, $03, $03, $00, $80, $20, $0A, $03, $03, $00, $14, $09, $0C, $08,
                     $0A, $0A, $14, $11, $0C, $08, $12, $0A, $14, $19, $0C, $08, $1A, $0A, $14, $21, $0C, $08, $22, $0A, $80, $08,
                     $10, $03, $03, $00, $80, $10, $10, $03, $03, $00, $80, $18, $10, $03, $03, $00, $80, $20, $10, $03, $03, $00,
                     $14, $09, $12, $08, $0A, $10, $14, $11, $12, $08, $12, $10, $14, $19, $12, $08, $1A, $10, $14, $21, $12, $08,
                     $22, $10, $FF]
    ubyte[] caveF = [$06, $14, $28, $3C, $00, $14, $15, $16, $17, $04, $06, $07, $08, $08, $96, $78,
                     $64, $5A, $50, $0E, $0A, $09, $00, $00, $10, $00, $00, $00, $32, $00, $00, $00,
                     $82, $01, $03, $0A, $04, $00, $82, $01, $06, $0A, $04, $00,
                     $82, $01, $09, $0A, $04, $00, $82, $01, $0C, $0A, $04, $00, $41, $0A, $03, $0D, $04, $14, $03, $05, $08, $04,
                     $05, $14, $03, $08, $08, $04, $08, $14, $03, $0B, $08, $04, $0B, $14, $03, $0E, $08, $04, $0E, $82, $1D, $03,
                     $0A, $04, $00, $82, $1D, $06, $0A, $04, $00, $82, $1D, $09, $0A, $04, $00, $82, $1D, $0C, $0A, $04, $00, $41,
                     $1D, $03, $0D, $04, $14, $24, $05, $08, $23, $05, $14, $24, $08, $08, $23, $08, $14, $24, $0B, $08, $23, $0B,
                     $14, $24, $0E, $08, $23, $0E, $25, $03, $14, $04, $26, $14, $FF]
    ubyte[] caveG = [$07, $4B, $0A, $14, $02, $07, $08, $0A, $09, $0F, $14, $19, $19, $19, $78, $78,
                     $78, $78, $78, $09, $0A, $0D, $00, $00, $00, $10, $08, $00, $64, $28, $02, $00,
                     $42, $01, $07, $0C, $02, $42, $1C, $05, $0B, $02, $7A, $13,
                     $15, $02, $02, $14, $04, $06, $14, $04, $0E, $14, $04, $16, $14, $22, $04, $14, $22, $0C, $14, $22, $16, $25,
                     $14, $03, $04, $27, $07, $FF]
    ubyte[] caveH = [$08, $14, $0A, $14, $01, $03, $04, $05, $06, $0A, $0F, $14, $14, $14, $78, $6E,
                     $64, $5A, $50, $02, $0E, $09, $00, $00, $00, $10, $08, $00, $5A, $32, $02, $00,
                     $14, $04, $06, $14, $22, $04, $14, $22, $0C, $04, $00, $05,
                     $25, $14, $03, $42, $01, $07, $0C, $02, $42, $01, $0F, $0C, $02, $42, $1C, $05, $0B, $02, $42, $1C, $0D, $0B,
                     $02, $43, $0E, $11, $08, $02, $14, $0C, $10, $00, $0E, $12, $14, $13, $12, $41, $0E, $0F, $08, $02, $FF]
    ubyte[] intermission2 = [
                     $12, $14, $0A, $00, $0A, $0B, $0C, $0D, $0E, $10, $10, $10, $10, $10, $0F, $0F,
                     $0F, $0F, $0F, $06, $0F, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
                     $87, $00, $02, $28, $16, $07, $87, $00, $02, $14, $0C, $01,
                     $50, $01, $03, $09, $03, $48, $02, $03, $08, $03, $54, $01, $05, $08, $03, $50, $01, $06, $07, $03, $50, $12,
                     $03, $09, $05, $54, $12, $05, $08, $05, $50, $12, $06, $07, $05, $25, $01, $04, $04, $12, $04, $FF]
    ubyte[] caveI = [$09, $14, $05, $0A, $64, $89, $8C, $FB, $33, $4B, $4B, $50, $55, $5A, $96, $96,
                     $82, $82, $78, $08, $04, $09, $00, $00, $10, $14, $00, $00, $F0, $78, $00, $00,
                     $82, $05, $0A, $0D, $0D, $00, $01, $0C, $0A, $82, $19, $0A,
                     $0D, $0D, $00, $01, $1F, $0A, $42, $11, $12, $09, $02, $40, $11, $13, $09, $02, $25, $07, $0C, $04, $08, $0C,
                     $FF]
    ubyte[] caveJ = [$0A, $14, $19, $3C, $00, $00, $00, $00, $00, $0C, $0C, $0C, $0C, $0C, $96, $82,
                     $78, $6E, $64, $06, $08, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
                     $25, $0D, $03, $04, $27, $16, $54, $05, $04, $11, $03, $54,
                     $15, $04, $11, $05, $80, $05, $0B, $11, $03, $08, $C2, $01, $04, $15, $11, $00, $0D, $04, $C2, $07, $06, $0D,
                     $0D, $00, $0D, $06, $C2, $09, $08, $09, $09, $00, $0D, $08, $C2, $0B, $0A, $05, $05, $00, $0D, $0A, $82, $03,
                     $06, $03, $0F, $08, $00, $04, $06, $54, $04, $10, $04, $04, $FF]
    ubyte[] caveK = [$0B, $14, $32, $00, $00, $04, $66, $97, $64, $06, $06, $06, $06, $06, $78, $78,
                     $96, $96, $F0, $0B, $08, $09, $00, $00, $00, $10, $08, $00, $64, $50, $02, $00,
                     $42, $0A, $03, $09, $04, $42, $14, $03, $09, $04, $42, $1E,
                     $03, $09, $04, $42, $09, $16, $09, $00, $42, $0C, $0F, $11, $02, $42, $05, $0B, $09, $02, $42, $0F, $0B, $09,
                     $02, $42, $19, $0B, $09, $02, $42, $1C, $13, $0B, $01, $14, $04, $03, $14, $0E, $03, $14, $18, $03, $14, $22,
                     $03, $14, $04, $16, $14, $23, $15, $25, $14, $14, $04, $26, $11, $FF]
    ubyte[] caveL = [$0C, $14, $14, $00, $00, $3C, $02, $3B, $66, $13, $13, $0E, $10, $15, $B4, $AA,
                     $A0, $A0, $A0, $0C, $0A, $09, $00, $00, $00, $10, $14, $00, $3C, $32, $09, $00,
                     $42, $0A, $05, $12, $04, $42, $0E, $05, $12, $04, $42, $12,
                     $05, $12, $04, $42, $16, $05, $12, $04, $42, $02, $06, $0B, $02, $42, $02, $0A, $0B, $02, $42, $02, $0E, $0F,
                     $02, $42, $02, $12, $0B, $02, $81, $1E, $04, $04, $04, $00, $08, $20, $05, $81, $1E, $09, $04, $04, $00, $08,
                     $20, $0A, $81, $1E, $0E, $04, $04, $00, $08, $20, $0F, $25, $03, $14, $04, $27, $16, $FF]
    ubyte[] intermission3 = [
                     $13, $04, $0A, $00, $0A, $0B, $0C, $0D, $0E, $0E, $0E, $0E, $0E, $0E, $14, $14,
                     $14, $14, $14, $06, $08, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
                     $87, $00, $02, $28, $16, $07, $87, $00, $02, $14, $0C, $00,
                     $54, $01, $0C, $12, $02, $88, $0F, $09, $04, $04, $08, $25, $08, $03, $04, $12, $07, $FF]
    ubyte[] caveM = [$0D, $8C, $05, $08, $00, $01, $02, $03, $04, $32, $37, $3C, $46, $50, $A0, $9B,
                     $96, $91, $8C, $06, $08, $0D, $00, $00, $10, $00, $00, $00, $28, $00, $00, $00,
                     $25, $12, $03, $04, $0A, $03, $3A, $14, $03, $42, $05, $12,
                     $1E, $02, $70, $05, $13, $1E, $02, $50, $05, $14, $1E, $02, $C1, $05, $15, $1E, $02, $FF]
    ubyte[] caveN = [$0E, $14, $0A, $14, $00, $00, $00, $00, $00, $1E, $23, $28, $2A, $2D, $96, $91,
                     $8C, $87, $82, $0C, $08, $09, $00, $00, $10, $00, $00, $00, $00, $00, $00, $00,
                     $81, $0A, $0A, $0D, $0D, $00, $70, $0B, $0B, $0C, $03, $C1,
                     $0C, $0A, $03, $0D, $C1, $10, $0A, $03, $0D, $C1, $14, $0A, $03, $0D, $50, $16, $08, $0C, $02, $48, $16, $07,
                     $0C, $02, $C1, $17, $06, $03, $04, $C1, $1B, $06, $03, $04, $C1, $1F, $06, $03, $04, $25, $03, $03, $04, $27,
                     $14, $FF]
    ubyte[] caveO = [$0F, $08, $0A, $14, $01, $1D, $1E, $1F, $20, $0F, $14, $14, $19, $1E, $78, $78,
                     $78, $78, $8C, $08, $0E, $09, $00, $00, $00, $10, $08, $00, $64, $50, $02, $00,
                     $42, $02, $04, $0A, $03, $42, $0F, $0D, $0A, $01, $41, $0C,
                     $0E, $03, $02, $43, $0C, $0F, $03, $02, $04, $14, $16, $25, $14, $03, $FF]
    ubyte[] caveP = [$10, $14, $0A, $14, $01, $78, $81, $7E, $7B, $0C, $0F, $0F, $0F, $0C, $96, $96,
                     $96, $96, $96, $09, $0A, $09, $00, $00, $10, $00, $00, $00, $32, $00, $00, $00,
                     $25, $01, $03, $04, $27, $04, $81, $08, $13, $04, $04, $00,
                     $08, $0A, $14, $C2, $07, $0A, $06, $08, $43, $07, $0A, $06, $02, $81, $10, $13, $04, $04, $00, $08, $12, $14,
                     $C2, $0F, $0A, $06, $08, $43, $0F, $0A, $06, $02, $81, $18, $13, $04, $04, $00, $08, $1A, $14, $81, $20, $13,
                     $04, $04, $00, $08, $22, $14, $FF]
    ubyte[] intermission4 = [
                     $14, $03, $1E, $00, $00, $00, $00, $00, $00, $06, $06, $06, $06, $06, $14, $14,
                     $14, $14, $14, $06, $08, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
                     $87, $00, $02, $28, $16, $07, $87, $00, $02, $14, $0C, $01,
                     $D0, $0B, $03, $03, $02, $80, $0B, $07, $03, $06, $00, $43, $0B, $06, $03, $02, $43, $0B, $0A, $03, $02, $50,
                     $08, $07, $03, $03, $25, $03, $03, $04, $09, $0A, $FF]

}


bd1demo {

    ; The format of the demo data is as follows.
    ; The low nybble of each byte indicates the direction that Rockford is to move
    ; ($0 = end of demo, $7 = Right, $B = Left, $D = Down, $E = Up, $F = no movement).
    ; The high nybble indicates the number of times (number of frames) to apply that movement.
    ; The demo finishes when it hits $00. So for example,
    ; $FF means no movement for 15 turns, $1E means move up one space, $77 means move right 7 spaces, etc.
    ; (details: https://www.elmerproductions.com/sp/peterb/insideBoulderdash.html)
    ubyte[] CAVE_A_DEMO = [
        $4F, $1E, $77, $2D, $97, $4F, $2D, $47, $3E, $1B, $4F, $1E, $B7, $1D, $27,
        $4F, $6D, $17, $4D, $3B, $4F, $1D, $1B, $47, $3B, $4F, $4E, $5B, $3E, $5B, $4D,
        $3B, $5F, $3E, $AB, $1E, $3B, $1D, $6B, $4D, $17, $4F, $3D, $47, $4D, $4B, $2E,
        $27, $3E, $A7, $A7, $1D, $47, $1D, $47, $2D, $5F, $57, $4E, $57, $6F, $1D, $00
    ]

    ubyte demo_step
    ubyte repeats
    ubyte direction
    sub init() {
        demo_step = 0
        repeats = 0
        direction = 0
    }

    sub set_joy_direction(ubyte d) {
        cave.joy_fire = false
        cave.joy_left = false
        cave.joy_right = false
        cave.joy_up = false
        cave.joy_down = false
        when d {
            $7 -> cave.joy_right=true
            $b -> cave.joy_left=true
            $d -> cave.joy_down=true
            $e -> cave.joy_up=true
        }
    }

    sub get_movement() {
        if repeats==255
            return
        if repeats {
            repeats--
            set_joy_direction(direction)
        } else {
            ubyte move = CAVE_A_DEMO[demo_step]
            direction = move&15
            if direction==0 {
                repeats = 255   ; end of demo
                set_joy_direction(0)
            } else {
                repeats = move>>4
                set_joy_direction(direction)
            }
            repeats--
            demo_step++
        }
    }
}