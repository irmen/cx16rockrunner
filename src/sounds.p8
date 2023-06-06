%import psg

; super high priority sounds: timeout 
; high priority sounds: crack - amoeba - magic wall
; mid priority: rockford moving.
; low priority: all other sounds.
; To convert SID values to hertz, multiply by (1,022,900/16,777,216) = 0.06096959114074707
; To convert Hertz to Vera freq, divide by (48828.125 / (2**17)) = 0.3725290298461914
; So to convert SID value directly to Vera freq, multiply by 0.163664
;    attack time:    MAXVOL/15/attack  seconds.    higher value = faster attack.
;    sustain time:   sustain/60 seconds    higher sustain value = longer sustain (!).
;    release time:   MAXVOL/15/release seconds.   higher vaule = faster release.


sounds {
    const ubyte VOICE_EXPLOSION = 8
    const ubyte VOICE_DIAMONDS = 9
    const ubyte VOICE_BOULDERS = 10
    const ubyte VOICE_CRACK = 11
    const ubyte VOICE_TIMEOUTUNCOVERBONUS = 12
    const ubyte VOICE_AMOEBA = 13
    const ubyte VOICE_MAGICWALL = 14
    const ubyte VOICE_ROCKFORDMOVE = 15

    sub explosion() {
        psg.voice(VOICE_EXPLOSION, psg.LEFT|psg.RIGHT, 63, psg.NOISE, 0)
        psg.freq(VOICE_EXPLOSION, 846)
        psg.envelope(VOICE_EXPLOSION, 63, 250, 0, 2)
    }

    sub diamond() {
        psg.voice(VOICE_DIAMONDS, psg.LEFT|psg.RIGHT, 63, psg.TRIANGLE, 0)
        uword f = (math.rndw() % 5070) + 5614   ; random between 5614 and 10684
        f &= %1111111100011111
        f |= %0000000011000000
        psg.freq(VOICE_DIAMONDS, f)
        psg.envelope(VOICE_DIAMONDS, 63, 250, 1, 18)
    }

    sub diamond_pickup() {
        psg.voice(VOICE_DIAMONDS, psg.LEFT|psg.RIGHT, 63, psg.TRIANGLE, 0)
        psg.freq(VOICE_DIAMONDS, 856)
        psg.envelope(VOICE_DIAMONDS, 63, 250, 1, 18)
    }

    sub boulder() {
        psg.voice(VOICE_BOULDERS, psg.LEFT|psg.RIGHT, 63, psg.NOISE, 0)
        psg.freq(VOICE_BOULDERS, 2085)
        psg.envelope(VOICE_BOULDERS, 63, 250, 1, 30)
    }

    sub crack() {
        psg.voice(VOICE_CRACK, psg.LEFT|psg.RIGHT, 63, psg.NOISE, 0)
        psg.freq(VOICE_CRACK, 5977)
        psg.envelope(VOICE_CRACK, 63, 250, 1, 10)
    }

    sub timeout(ubyte timeleft) {
        psg.voice(VOICE_TIMEOUTUNCOVERBONUS, psg.LEFT|psg.RIGHT, 63, psg.TRIANGLE, 0)
        if timeleft>10
            timeleft=10
        uword[11] freqs = [1676, 1634, 1592, 1550, 1508, 1466, 1424, 1382, 1340, 1299, 1257]
        psg.freq(VOICE_TIMEOUTUNCOVERBONUS, freqs[timeleft])
        psg.envelope(VOICE_TIMEOUTUNCOVERBONUS, 63, 255, 1, 4)
    }

    sub uncover() {
        psg.voice(VOICE_TIMEOUTUNCOVERBONUS, psg.LEFT|psg.RIGHT, 60, psg.TRIANGLE, 0)
        psg.freq(VOICE_TIMEOUTUNCOVERBONUS, math.rndw() % 5321 + 4190)
        psg.envelope(VOICE_TIMEOUTUNCOVERBONUS, 60, 250, 1, 25)
    }

    sub amoeba() {
        psg.voice(VOICE_AMOEBA, psg.LEFT|psg.RIGHT, 55, psg.TRIANGLE, 0)
        psg.freq(VOICE_AMOEBA, math.rndw() % 293 + 335)   ; random between 335 and 628
        psg.envelope(VOICE_AMOEBA, 55, 255, 0, 5)
    }

    sub magicwall() {
        psg.voice(VOICE_MAGICWALL, psg.LEFT|psg.RIGHT, 55, psg.TRIANGLE, 0)
        uword f = (math.rndw() % 1047) + 5614   ; random between 5614 and 6661
        f &= %1111001111100000
        f |= %0001000011000000
        psg.freq(VOICE_MAGICWALL, f)
        psg.envelope(VOICE_MAGICWALL, 55, 250, 1, 40)
    }

    sub bonus(ubyte secsremaining) {
        psg.voice(VOICE_TIMEOUTUNCOVERBONUS, psg.LEFT|psg.RIGHT, 56, psg.TRIANGLE, 0)
        uword z = secsremaining + 16
        ubyte x
        for x in 15 downto 1 {
            psg.freq(VOICE_TIMEOUTUNCOVERBONUS, (z-x*2)*64)
            psg.envelope(VOICE_TIMEOUTUNCOVERBONUS, 56, 250, 1, 200)
            repeat 255 {
                %asm {{
                    nop
                }}
            }
        }
    }

    sub rockfordmove_space() {
        psg.voice(VOICE_ROCKFORDMOVE, psg.LEFT|psg.RIGHT, 32, psg.NOISE, 0)
        psg.freq(VOICE_ROCKFORDMOVE, 2220)
        psg.envelope(VOICE_ROCKFORDMOVE, 32, 160, 0, 40)
    }

    sub rockfordmove_dirt() {
        psg.voice(VOICE_ROCKFORDMOVE, psg.LEFT|psg.RIGHT, 32, psg.NOISE, 0)
        psg.freq(VOICE_ROCKFORDMOVE, 6913)
        psg.envelope(VOICE_ROCKFORDMOVE, 32, 160, 0, 40)
    }

    sub expanding_wall() {
        psg.voice(VOICE_BOULDERS, psg.LEFT|psg.RIGHT, 48, psg.NOISE, 0)
        psg.freq(VOICE_BOULDERS, 385)
        psg.envelope(VOICE_BOULDERS, 48, 250, 1, 20)
    }
}

music {

    ; details about the boulderdash music can be found here:
    ; https://www.elmerproductions.com/sp/peterb/sounds.html#Theme%20tune
    ; playable sheet music of the tune: https://musescore.com/user/33594939/scores/5866869

    sub init() {
         playback_enabled = false
         psg.silent()
         psg.voice(0, psg.LEFT, 0, psg.TRIANGLE, 0)
         psg.voice(1, psg.RIGHT, 0, psg.TRIANGLE, 0)
         restart()
    }

    sub restart() {
        note_idx = 0
    }

    bool playback_enabled
    ubyte note_idx
    ubyte update_cnt

    sub update() {
        if not playback_enabled
            return

        update_cnt++
        if update_cnt==10
            update_cnt = 0
        else
            return
        uword note = notes[note_idx]
        note_idx++
        if note_idx >= len(notes)
            note_idx = 0
        ubyte note0 = lsb(note)
        ubyte note1 = msb(note)
        psg.freq(0, vera_freqs[note0])
        psg.freq(1, vera_freqs[note1])
        psg.envelope(0, 63, 255, 0, 6)
        psg.envelope(1, 63, 255, 0, 6)
    }

    uword[] notes = [
        $1622, $1d26, $2229, $252e, $1424, $1f27, $2029, $2730,
        $122a, $122c, $1e2e, $1231, $202c, $3337, $212d, $3135,
        $1622, $162e, $161d, $1624, $1420, $1430, $1424, $1420,
        $1622, $162e, $161d, $1624, $1e2a, $1e3a, $1e2e, $1e2a,
        $142c, $142c, $141b, $1422, $1c28, $1c38, $1c2c, $1c28,
        $111d, $292d, $111f, $292e, $0f27, $0f27, $1633, $1627,
        $162e, $162e, $162e, $162e, $222e, $222e, $162e, $162e,
        $142e, $142e, $142e, $142e, $202e, $202e, $142e, $142e,
        $162e, $322e, $162e, $332e, $222e, $322e, $162e, $332e,
        $142e, $322e, $142e, $332e, $202c, $302c, $142c, $312c,
        $162e, $163a, $162e, $3538, $222e, $2237, $162e, $3135,
        $142c, $1438, $142c, $1438, $202c, $2033, $142c, $1438,
        $162e, $322e, $162e, $332e, $222e, $322e, $162e, $332e,
        $142e, $322e, $142e, $332e, $202c, $302c, $142c, $312c,
        $2e32, $292e, $2629, $2226, $2c30, $272c, $2427, $1420,
        $3532, $322e, $2e29, $2926, $2730, $242c, $2027, $1420
    ]

    uword[] vera_freqs = [
        0,0,0,0,0,0,0,0,0,0,   ; first 10 notes are not used
        120, 127, 135, 143, 152, 160, 170, 180, 191, 203,
        215, 227, 240, 255, 270, 287, 304, 320, 341, 360,
        383, 405, 429, 455, 479, 509, 541, 573, 607, 640,
        682, 720, 766, 810, 859, 910, 958, 1019, 1082, 1147,
        1215, 1280, 1364, 1440, 1532, 1621, 1718, 1820, 1917]

}
