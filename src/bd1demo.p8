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
        joystick.clear()
        when d {
            $7 -> joystick.right=true
            $b -> joystick.left=true
            $d -> joystick.down=true
            $e -> joystick.up=true
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