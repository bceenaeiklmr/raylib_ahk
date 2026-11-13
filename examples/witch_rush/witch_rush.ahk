#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

; ==============================================================================
; JUNK FOOD WITCH: BROOM RUSH
; A retro 2D pixel art arcade game powered by raylib.ahk
; Workspace: examples\witch_rush
;
; Story:
;   Bored Bernice is a delightfully chubby, permanently unimpressed witch.
;   She refuses to fly on a boring healthy diet. Keep her airborne by chugging
;   neon energy drinks and devouring greasy junk food while dodging horrifying
;   healthy obstacles (broccoli, carrots, smug apples, and zero-calorie tap water)!
;
; Controls:
;   W, A, S, D / Arrows / Mouse : Fly & Maneuver
;   Space                       : Sugar Dash (speed burst through danger)
;   P                           : Pause / Resume
;   M                           : Mute / Unmute Sound
;   R                           : Restart Round
;   Escape                      : Quit
; ==============================================================================

#Include ..\..\lib\raylib.ahk

; --- Parse CLI options (/auto[:ms], /shot:name, /play) for testing ---
AutoExit := 0, ShotName := "", ShotPath := "", StartInPlay := false
for Arg in A_Args {
    if SubStr(Arg, 1, 5) = "/auto" {
        Colon := InStr(Arg, ":")
        AutoExit := Colon ? Integer(SubStr(Arg, Colon + 1)) : 3000
    } else if SubStr(Arg, 1, 5) = "/shot" {
        Colon := InStr(Arg, ":")
        ShotName := Colon ? SubStr(Arg, Colon + 1) : "witch_game"
    } else if Arg = "/play" {
        StartInPlay := true
    }
}
if ShotName != "" {
    if !InStr(ShotName, ".")
        ShotName .= ".png"
    DirCreate(A_ScriptDir "\docs")
    ShotPath := A_ScriptDir "\docs\" ShotName
}

; --- Window Configuration ---
ScreenWidth := 960, ScreenHeight := 540
ScaleFactor := 3.0  ; Chunky 3x pixel art

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(ScreenWidth, ScreenHeight, "Junk Food Witch: Broom Rush (raylib.ahk)")

; ==============================================================================
; AUDIO SYNTHESIS IN MEMORY (Zero external sound files required)
; ==============================================================================
RL.InitAudioDevice()
AudioReady := RL.IsAudioDeviceReady()
SoundMuted := false

PutTag(Chars, Buf, Pos) {
    Loop 4
        NumPut("UChar", Ord(SubStr(Chars, A_Index, 1)), Buf, Pos + A_Index - 1)
}

SynthSound(Duration, Generator) {
    if !AudioReady
        return 0
    Rate := 44100
    N := Integer(Rate * Duration)
    Buf := Buffer(44 + N * 2, 0)
    PutTag("RIFF", Buf, 0)
    NumPut("UInt", 36 + N * 2, Buf, 4)
    PutTag("WAVE", Buf, 8)
    PutTag("fmt ", Buf, 12)
    NumPut("UInt", 16, Buf, 16)
    NumPut("UShort", 1, Buf, 20)
    NumPut("UShort", 1, Buf, 22)
    NumPut("UInt", Rate, Buf, 24)
    NumPut("UInt", Rate * 2, Buf, 28)
    NumPut("UShort", 2, Buf, 32)
    NumPut("UShort", 16, Buf, 34)
    PutTag("data", Buf, 36)
    NumPut("UInt", N * 2, Buf, 40)
    Loop N {
        t := (A_Index - 1) / Rate
        val := Generator(t, Duration)
        val := Max(-32767, Min(32767, val))
        NumPut("Short", Integer(val), Buf, 44 + (A_Index - 1) * 2)
    }
    W := RL.LoadWaveFromMemory(".wav", Buf, Buf.Size)
    if (RL.Wave_FrameCount(W) != N)
        return 0
    return RL.LoadSoundFromWave(W)
}

; 1. Drink Slurp / Gulp Sound
GenDrink(t, dur) {
    freq := 300 + 700 * (t / dur)
    env := (1 - t / dur)
    return Sin(6.28318 * freq * t) * 11000 * env
}
SndDrink := SynthSound(0.14, GenDrink)

; 2. Food Crunch Sound
GenCrunch(t, dur) {
    freq := 220 + 380 * Sin(t * 120)
    noise := (Mod(Integer(t * 44100 * 17), 100) - 50) / 50.0
    env := (1 - t / dur) ** 2
    return (Sin(6.28318 * freq * t) * 0.6 + noise * 0.4) * 12000 * env
}
SndCrunch := SynthSound(0.12, GenCrunch)

; 3. Vegetable Hit Sound
GenHurt(t, dur) {
    freq := 180 - 110 * (t / dur)
    saw := Mod(t * freq, 1.0) - 0.5
    env := (1 - t / dur)
    return saw * 14000 * env
}
SndHurt := SynthSound(0.25, GenHurt)

; 4. Sugar Rush Fanfare
GenRush(t, dur) {
    step := Integer(t / 0.087)
    notes := [523.25, 659.25, 783.99, 1046.50]
    freq := notes[Min(step + 1, 4)]
    env := 1.0 - Mod(t, 0.087) / 0.087
    return Sin(6.28318 * freq * t) * 11000 * env
}
SndRush := SynthSound(0.35, GenRush)

; 5. Dash Whoosh Sound
GenDash(t, dur) {
    noise := (Mod(Integer(t * 44100 * 23), 100) - 50) / 50.0
    freq := 600 - 450 * (t / dur)
    env := Sin(3.14159 * (t / dur))
    return (Sin(6.28318 * freq * t) * 0.3 + noise * 0.7) * 10000 * env
}
SndDash := SynthSound(0.18, GenDash)

; 6. Game Over Sad Descending Tone
GenGameOver(t, dur) {
    freq := 380 - 240 * (t / dur)
    env := (1 - t / dur)
    return (Sin(6.28318 * freq * t) + 0.3 * Sin(12.566 * freq * t)) * 9000 * env
}
SndGameOver := SynthSound(0.65, GenGameOver)

PlayAudio(snd) {
    if AudioReady && snd && !SoundMuted
        RL.PlaySound(snd)
}

; --- 8-Bit Background Music Stream ---
BgmStream := 0
bgmPath := A_ScriptDir "\music.wav"
if AudioReady && FileExist(bgmPath) {
    BgmStream := RL.LoadMusicStream(bgmPath)
    if RL.IsMusicValid(BgmStream) {
        RL.Music_Looping(BgmStream, 1)
        RL.SetMusicVolume(BgmStream, 0.38)
        RL.PlayMusicStream(BgmStream)
    }
}

; ==============================================================================
; SPRITE BUILDER & PIXEL ART GENERATION
; ==============================================================================
BuildTexture(rows, pal) {
    h := rows.Length
    w := StrLen(rows[1])
    img := RL.GenImageColor(w, h, RL.BLANK)
    for y, row in rows {
        loop StrLen(row) {
            x := A_Index
            ch := SubStr(row, x, 1)
            if pal.Has(ch) && pal[ch] != RL.BLANK
                RL.ImageDrawPixel(img, x - 1, y - 1, pal[ch])
        }
    }
    tex := RL.LoadTextureFromImage(img)
    RL.SetTextureFilter(tex, RL.TEXTURE_FILTER_POINT)
    RL.UnloadImage(img)
    return { tex: tex, w: w, h: h }
}

; 1. Witch Palettes & Frames (32x24)
WitchPal := Map(
    ".", RL.BLANK, "K", 0x1A1026FF, "H", 0x2C1D4DFF, "h", 0x513885FF,
    "B", 0xF5CD2FFF, "F", 0xBDD788FF, "E", 0x2A3319FF, "W", 0xFFFFFFFF,
    "R", 0xD66576FF, "P", 0x48246BFF, "p", 0x6E399EFF, "L", 0x9B59D4FF,
    "S", 0x754320FF, "s", 0x9E6034FF, "T", 0xE8B838FF, "t", 0xAD8018FF,
    "C", 0x00E5FFFF, "Y", 0xFFEE00FF
)

Witch1_Rows := [
    "................KKKK............",
    "...............KHHHhK...........",
    "..............KHHHHhhK..........",
    ".............KHHHHHhhhK.........",
    "............KHHHHHHhhhhK........",
    "...........KHHHHHHHhhhhhK.......",
    "..........KBBBBBBBBBBBBBK.......",
    "........KKKHHHHHHHHHHHHHKKK.....",
    ".......KHHHHHHHHHHHHHHHHHHHK....",
    "........KKKKKFFFFFFFFKKKKKK.....",
    "............KFEFFEFEK...........",
    "............KFFFRFFFK...........",
    "...........KKFFFFFFFFKK.........",
    "..........KPPPPFFFFFFPPPK.......",
    ".........KPPPpLLPPPPLLppPK......",
    "........KPPPpLLLLLLLLLppPK......",
    ".TTTTT.KPPPPpLLLLLLLLLppPKK.....",
    "TTTTTSSKPPPPpLLLLLLLLCppPKKSSSSS",
    "tttttSSKPPPPpLLLLLLLLCppPKKSSsss",
    ".TTTTT.KPPPPpLLLLLLLLLppPKK.....",
    "........KPPPPPPPPPPPPPPPK.......",
    ".........KKKKKPPPPPppKKK........",
    ".............KFFFFK.............",
    ".............KKKKKK............."
]

Witch2_Rows := [
    "................KKKK............",
    "...............KHHHhK...........",
    "..............KHHHHhhK..........",
    ".............KHHHHHhhhK.........",
    "............KHHHHHHhhhhK........",
    "...........KHHHHHHHhhhhhK.......",
    "..........KBBBBBBBBBBBBBK.......",
    "........KKKHHHHHHHHHHHHHKKK.....",
    ".......KHHHHHHHHHHHHHHHHHHHK....",
    "........KKKKKFFFFFFFFKKKKKK.....",
    "............KFEFFEFEK...........",
    "............KFFFRFFFK...........",
    "...........KKFFFFFFFFKK.........",
    "..........KPPPPFFFFFFPPPK.......",
    ".........KPPPpLLPPPPLLppPK......",
    "........KPPPpLLLLLLLLLppPK......",
    "..TTTTTKPPPPpLLLLLLLLLppPKK.....",
    "TTTTTSSKPPPPpLLLLLLLLCppPKKSSSSS",
    "tttttSSKPPPPpLLLLLLLLCppPKKSSsss",
    "..TTTTTKPPPPpLLLLLLLLLppPKK.....",
    "........KPPPPPPPPPPPPPPPK.......",
    ".........KKKKKPPPPPppKKK........",
    ".............KFFFFK.............",
    ".............KKKKKK............."
]

; 2. Items Palettes & Sprites
ItemPal := Map(
    ".", RL.BLANK, "K", 0x1A1423FF, "N", 0x39FF14FF, "n", 0x1DB300FF,
    "Y", 0xFFEA00FF, "M", 0x22252AFF, "S", 0xD0D7DEFF, "R", 0xD62828FF,
    "r", 0x9E1B1BFF, "W", 0xFFFFFFFF, "C", 0xB87333FF, "y", 0xFFB703FF,
    "p", 0xBA181BFF, "D", 0xDE9B52FF, "P", 0xFF69B4FF, "B", 0x00B4D8FF,
    "b", 0xC98A4CFF, "m", 0x5C2E14FF, "g", 0x55A630FF
)

SprEnergy_Rows := [
    "...KKKKKK...",
    "..KSSSSSSK..",
    ".KSSSSSSSSK.",
    ".KMMMMMMMMK.",
    ".KMMMYYMMMK.",
    ".KMMYYYYMMK.",
    ".KMNYYYYNMK.",
    ".KMNNYYNNMK.",
    ".KMNNYYNNMK.",
    ".KMNYYYYNMK.",
    ".KMMYYYYMMK.",
    ".KMMMYYMMMK.",
    ".KMMMMMMMMK.",
    ".KSSSSSSSSK.",
    "..KSSSSSSK..",
    "...KKKKKK..."
]

SprSoda_Rows := [
    "...KKKKKK...",
    "..KSSSSSSK..",
    ".KSSSSSSSSK.",
    ".KRRRRRRRRK.",
    ".KrRRRRRRRK.",
    ".KrRWWRRRRK.",
    ".KrRRWWRRRK.",
    ".KrRRRWWRRK.",
    ".KrRRRRWWRK.",
    ".KrRWWRRRRK.",
    ".KrRRWWRRRK.",
    ".KrRRRRRRRK.",
    ".KRRRRRRRRK.",
    ".KSSSSSSSSK.",
    "..KSSSSSSK..",
    "...KKKKKK..."
]

SprPizza_Rows := [
    "................",
    "...KKKKKKKKKK...",
    "..KCCCCCCCCCCK..",
    "..KyyyyyyyyyyK..",
    "...KyyppyyyyK...",
    "...KyypppyyK....",
    "....KyyyyyyK....",
    "....KyyppyyK....",
    ".....KyyppyK....",
    ".....KyyyyK.....",
    "......KyyyK.....",
    "......KyyK......",
    ".......KyK......",
    ".......KK.......",
    "........K.......",
    "................"
]

SprDonut_Rows := [
    ".....KKKKKK.....",
    "...KKPPPPPPKK...",
    "..KPPWPPBPPYPK..",
    ".KPPPGPPPPPPPK..",
    ".KPPKKKKKKPPPPK.",
    "KPPKK....KKPPPK.",
    "KPDD......DDPPK.",
    "KPDD......DDPPK.",
    "KPDDKK....KDDDK.",
    ".KDDKKKKKKKDDDK.",
    ".KDDDDDDDDDDDDK.",
    "..KDDDDDDDDDDK..",
    "...KKDDDDDDKK...",
    ".....KKKKKK.....",
    "................",
    "................"
]

SprBurger_Rows := [
    ".....KKKKKK.....",
    "...KKbbbbbbKK...",
    "..KbbWbbWbbbbK..",
    ".KbbbbbbbbbbbbK.",
    ".KggggggggggggK.",
    ".KrrrrrrrrrrrrK.",
    ".KyyyyyyyyyyyyK.",
    ".KmmmmmmmmmmmmK.",
    ".KmmmmmmmmmmmmK.",
    ".KbbbbbbbbbbbbK.",
    "..KbbbbbbbbbbK..",
    "...KKbbbbbbKK...",
    ".....KKKKKK.....",
    "................",
    "................",
    "................"
]

; 3. Enemy Sprites
EnemyPal := Map(
    ".", RL.BLANK, "K", 0x141F14FF, "G", 0x1B4D1BFF, "L", 0x38B000FF,
    "l", 0x70E000FF, "S", 0x99D98CFF, "E", 0x0A0F0AFF, "W", 0xFFFFFFFF,
    "O", 0xFF6B00FF, "o", 0xCC4400FF, "T", 0x38B000FF, "k", 0x203A4CFF,
    "w", 0x48CAE4FF, "I", 0xCAF0F8FF, "V", 0xFFFFFFFF, "A", 0xD90429FF,
    "a", 0x9B031CFF, "J", 0x74C69DFF
)

SprBroccoli_Rows := [
    ".....KKKKKK.....",
    "...KKLLGGLLKK...",
    "..KLLGGGGGGLLK..",
    ".KLLGGGGGGGGLLK.",
    ".KLGGGGGGGGGGLLK",
    ".KLGGEGGGGEGLLK.",
    ".KLGGEEGGGEELLK.",
    "..KLGGGGGGGGLLK.",
    "...KKLLGGLLKK...",
    ".....KKSSKK.....",
    "....KSSSSSSK....",
    "....KSSSSSSK....",
    "....KSSSSSSK....",
    ".....KKSSKK.....",
    "......KKKK......",
    "................"
]

SprCarrot_Rows := [
    "................",
    ".TT.............",
    "TTTT............",
    ".TT.KKKKKKKK....",
    "..KKooOOOOOOKK..",
    ".KooOOOOEOOOOOOK",
    "KooOOOOOEEEOOOOO",
    "KooOOOOOOOOOOOOK",
    ".KooOOOOOOOOOKK.",
    "..KKooooooooKK..",
    "...KKKKKKKKKK...",
    "................",
    "................",
    "................",
    "................",
    "................"
]

SprWater_Rows := [
    "..kkkkkkkkkk..",
    "..kVwwwwwwVk..",
    "..kVwIIwwwwk..",
    "..kVwIIwwwwk..",
    "..kVwwwwwwVk..",
    "..kVwwwwwwVk..",
    "..kVwwwwwwVk..",
    "..kVwwwwwwVk..",
    "...kVwwwwVk...",
    "...kVwwwwVk...",
    "...kVwwwwVk...",
    "....kVwwVk....",
    "....kVwwVk....",
    ".....kVVk.....",
    ".....kkkk.....",
    ".............."
]

SprApple_Rows := [
    "......KK......",
    ".....KJJJ.....",
    "....K..K......",
    "...KKAAAKK....",
    "..KAAAAAAAAK..",
    ".KAAAAAAAAAAK.",
    ".KAAAAAAAAAAK.",
    ".KAAWEAAWEAAK.",
    ".KAAAAAAAAAAK.",
    ".KAAAAAAAAAAK.",
    "..KaAAAAAAaK..",
    "...KaAAAAaK...",
    "....KKKKKK....",
    ".............."
]

; 4. HUD Heart Sprites
SprHeart_Rows := [
    ".KK.KK.",
    "KRRKRRK",
    "KRRRRRK",
    "KRRRRRK",
    ".KRRRK.",
    "..KRK..",
    "...K..."
]
HeartPal := Map(".", RL.BLANK, "K", 0x1A1026FF, "R", 0xFF3366FF)

SprHeartEmpty_Rows := [
    ".KK.KK.",
    "K..K..K",
    "K.....K",
    "K.....K",
    ".K...K.",
    "..K.K..",
    "...K..."
]
HeartEmptyPal := Map(".", RL.BLANK, "K", 0x4D3B66FF)

; Build all textures
TexWitch1      := BuildTexture(Witch1_Rows, WitchPal)
TexWitch2      := BuildTexture(Witch2_Rows, WitchPal)
TexEnergy      := BuildTexture(SprEnergy_Rows, ItemPal)
TexSoda        := BuildTexture(SprSoda_Rows, ItemPal)
TexPizza       := BuildTexture(SprPizza_Rows, ItemPal)
TexDonut       := BuildTexture(SprDonut_Rows, ItemPal)
TexBurger      := BuildTexture(SprBurger_Rows, ItemPal)
TexBroccoli    := BuildTexture(SprBroccoli_Rows, EnemyPal)
TexCarrot      := BuildTexture(SprCarrot_Rows, EnemyPal)
TexWater       := BuildTexture(SprWater_Rows, EnemyPal)
TexApple       := BuildTexture(SprApple_Rows, EnemyPal)
TexHeart       := BuildTexture(SprHeart_Rows, HeartPal)
TexHeartEmpty  := BuildTexture(SprHeartEmpty_Rows, HeartEmptyPal)

; ==============================================================================
; CARTOON TOOLTIPS & SPEECH BUBBLES
; ==============================================================================
CurrentBubble := { text: "", timer: 0.0, maxTimer: 0.0, priority: 0, isHigh: false }
IdleSpeechTimer := 0.0
ConsecutiveCans := 0

BoringStories := [
    "WHEN I WAS A LITTLE GIRL, WE ONLY HAD TWO KINDS OF GRAVEL TO PLAY WITH...",
    "WHEN I WAS A LITTLE GIRL, MY BEST FRIEND WAS A DECORATIVE SQUASH...",
    "WHEN I WAS A LITTLE GIRL, I ATE A DIRT PIE AND IT WAS TOO DELICIOUS...",
    "WHEN I WAS A LITTLE GIRL, BROOMS HAD SPLINTERS AND WE LIKED IT...",
    "MY AUNT GERTRUDE ONCE STARED AT A WALL FOR FOURTEEN DAYS STRAIGHT...",
    "DID I TURN OFF THE CAULDRON? NAH, IT PROBABLY DRIED OUT DECADES AGO...",
    "I ONCE MET A GHOST. WE TALKED ABOUT THE HUMIDITY. VERY DRAMATIC.",
    "I ENJOY WATCHING DRIED PAINT CRACK. IT MOVES ALMOST TOO FAST FOR ME.",
    "BACK IN 1642, NOBODY TRIED TO PUT KALE IN MY FLYING FUEL...",
    "I SHOULD BUY MORE SOCKS. BROWN ONES. OR SLIGHTLY DIRT-COLORED ONES...",
    "ONCE A PRIEST TRIED TO EXORCISE ME. HE GOT SLEEPY AND TOOK A NAP.",
    "MY BROOM'S OIL WAS LAST CHANGED DURING THE RENAISSANCE...",
    "I USED TO HAVE A PET BAT, BUT IT WAS TOO FAST, SO I REPLACED IT WITH A SPONGE."
]

SayWitch(text, priority := 1, duration := 2.6, isHigh := false) {
    global CurrentBubble
    if CurrentBubble.timer <= 0 || priority >= CurrentBubble.priority {
        CurrentBubble.text := text
        CurrentBubble.timer := duration
        CurrentBubble.maxTimer := duration
        CurrentBubble.priority := priority
        CurrentBubble.isHigh := isHigh
    }
}

WrapText(text, maxChars := 26) {
    words := StrSplit(text, " ")
    lines := []
    current := ""
    for w in words {
        if current == ""
            current := w
        else if (StrLen(current) + 1 + StrLen(w) <= maxChars)
            current .= " " . w
        else {
            lines.Push(current)
            current := w
        }
    }
    if current != ""
        lines.Push(current)
    return lines
}

DrawWitchSpeech(text, targetX, targetY, isHighPriority := false) {
    if text == ""
        return

    fontSize := 18
    lineSpacing := 4
    lines := WrapText(text, 26)

    totalH := lines.Length * (fontSize + lineSpacing)
    startY := targetY - totalH - 12
    if startY < 52
        startY := targetY + PlayerH + 10

    textColor := isHighPriority ? 0xFFEE00FF : 0xFFFFFFFF
    shadowColor := 0x000000FF

    for idx, l in lines {
        lw := RL.MeasureText(l, fontSize)
        lx := targetX - lw / 2
        lx := Max(15, Min(ScreenWidth - lw - 15, lx))
        ly := startY + (idx - 1) * (fontSize + lineSpacing)

        ; Retro shadow for high contrast readability
        RL.DrawText(l, lx + 2, ly + 2, fontSize, shadowColor)
        RL.DrawText(l, lx, ly, fontSize, textColor)
    }
}

; ==============================================================================
; GAME STATE & VARIABLES
; ==============================================================================
STATE_TITLE    := 0
STATE_PLAYING  := 1
STATE_PAUSED   := 2
STATE_GAMEOVER := 3

GameState := StartInPlay ? STATE_PLAYING : STATE_TITLE
HighScore := 0

; Player entity
PlayerX := 120.0
PlayerY := 220.0
PlayerVx := 0.0
PlayerVy := 0.0
PlayerW := TexWitch1.w * ScaleFactor
PlayerH := TexWitch1.h * ScaleFactor
PlayerAngle := 0.0
PlayerHealth := 3
PlayerMaxHealth := 3
PlayerCaffeine := 40.0
SugarRushTimer := 0.0
InvulnTimer := 0.0
DashTimer := 0.0
DashCooldown := 0.0
DashMaxCooldown := 1.0
Score := 0
Calories := 0
Combo := 1
ComboTimer := 0.0
TotalJunkEaten := 0
TotalDrinksChugged := 0
TotalVegSmashed := 0
WitchAnimTick := 0.0
ShakeTimer := 0.0

; Entity collections
Items := []
Enemies := []
Particles := []
FloatingTexts := []

; Background stars
Stars := []
Loop 45 {
    Stars.Push({
        x: RL.GetRandomValue(0, ScreenWidth),
        y: RL.GetRandomValue(0, ScreenHeight - 90),
        size: RL.GetRandomValue(1, 3),
        speed: RL.GetRandomValue(10, 45) / 10.0,
        alpha: RL.GetRandomValue(140, 255)
    })
}

; Spawners
ItemSpawnTimer := 0.0
EnemySpawnTimer := 0.0
DifficultySpeed := 1.0

SpawnRandomItem(spawnX := 0) {
    global Items, ScreenWidth, ScreenHeight, ScaleFactor, DifficultySpeed
    global TexEnergy, TexSoda, TexPizza, TexDonut, TexBurger
    if spawnX == 0
        spawnX := ScreenWidth + 20

    rType := RL.GetRandomValue(1, 100)
    itemData := {}
    if rType <= 32 {
        itemData := { type: "energy", tex: TexEnergy, pts: 200, cal: 240, caff: 32.0, name: "MEGA BUZZ!" }
    } else if rType <= 60 {
        itemData := { type: "soda", tex: TexSoda, pts: 100, cal: 150, caff: 20.0, name: "COLA!" }
    } else if rType <= 78 {
        itemData := { type: "pizza", tex: TexPizza, pts: 160, cal: 380, caff: 12.0, name: "PIZZA!" }
    } else if rType <= 90 {
        itemData := { type: "donut", tex: TexDonut, pts: 130, cal: 290, caff: 15.0, name: "DONUT!" }
    } else {
        itemData := { type: "burger", tex: TexBurger, pts: 220, cal: 580, caff: 10.0, name: "BURGER!" }
    }

    Items.Push({
        tex: itemData.tex,
        type: itemData.type,
        pts: itemData.pts,
        cal: itemData.cal,
        caff: itemData.caff,
        name: itemData.name,
        x: spawnX,
        y: RL.GetRandomValue(40, ScreenHeight - 110),
        w: itemData.tex.w * ScaleFactor,
        h: itemData.tex.h * ScaleFactor,
        vx: -RL.GetRandomValue(180, 260) * DifficultySpeed,
        bobOffset: RL.GetRandomValue(0, 100) / 10.0
    })
}

SpawnRandomEnemy(spawnX := 0) {
    global Enemies, ScreenWidth, ScreenHeight, ScaleFactor, DifficultySpeed
    global TexBroccoli, TexCarrot, TexWater, TexApple
    if spawnX == 0
        spawnX := ScreenWidth + 20

    eType := RL.GetRandomValue(1, 4)
    enData := {}
    if eType == 1 {
        enData := { tex: TexBroccoli, pattern: "wave", name: "BROCCOLI!", speed: 200 }
    } else if eType == 2 {
        enData := { tex: TexCarrot, pattern: "missile", name: "CARROT!", speed: 330 }
    } else if eType == 3 {
        enData := { tex: TexWater, pattern: "drift", name: "TAP WATER!", speed: 170 }
    } else {
        enData := { tex: TexApple, pattern: "arc", name: "APPLE!", speed: 210 }
    }

    randY := RL.GetRandomValue(40, ScreenHeight - 110)
    Enemies.Push({
        tex: enData.tex,
        pattern: enData.pattern,
        name: enData.name,
        x: spawnX,
        y: randY,
        startY: randY,
        w: enData.tex.w * ScaleFactor,
        h: enData.tex.h * ScaleFactor,
        vx: -enData.speed * DifficultySpeed,
        vy: 0.0,
        tick: RL.GetRandomValue(0, 100) / 10.0
    })
}

; Reset Round
ResetGame() {
    global
    PlayerX := 120.0
    PlayerY := ScreenHeight / 2 - PlayerH / 2
    PlayerVx := 0.0
    PlayerVy := 0.0
    PlayerAngle := 0.0
    PlayerHealth := 3
    PlayerCaffeine := 40.0
    SugarRushTimer := 0.0
    InvulnTimer := 0.0
    DashTimer := 0.0
    DashCooldown := 0.0
    Score := 0
    Calories := 0
    Combo := 1
    ComboTimer := 0.0
    TotalJunkEaten := 0
    TotalDrinksChugged := 0
    TotalVegSmashed := 0
    ConsecutiveCans := 0
    DifficultySpeed := 1.0
    ShakeTimer := 0.0
    IdleSpeechTimer := 0.0
    Items := []
    Enemies := []
    Particles := []
    FloatingTexts := []
    GameState := STATE_PLAYING

    ; Pre-seed sky with floating snacks and a distant obstacle
    SpawnRandomItem(ScreenWidth * 0.45)
    SpawnRandomItem(ScreenWidth * 0.70)
    SpawnRandomItem(ScreenWidth * 0.95)
    SpawnRandomEnemy(ScreenWidth * 0.60)
    SpawnRandomEnemy(ScreenWidth * 0.85)

    SayWitch("TIME TO CONSUME SOME GARBAGE.", 1, 2.0)
}

if StartInPlay
    ResetGame()

; Floating text helper
AddFloatingText(text, x, y, color) {
    global FloatingTexts
    FloatingTexts.Push({
        text: text,
        x: x,
        y: y,
        vx: RL.GetRandomValue(-20, 20),
        vy: -70.0,
        color: color,
        life: 0.9,
        maxLife: 0.9
    })
}

; Particle helper
AddParticle(x, y, vx, vy, color, size, life) {
    global Particles
    Particles.Push({
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        color: color,
        size: size,
        life: life,
        maxLife: life
    })
}

; ==============================================================================
; INPUT HANDLING
; ==============================================================================
HandleInput(dt) {
    global PlayerVx, PlayerVy, PlayerX, PlayerY, PlayerCaffeine, DashTimer, DashCooldown, ShakeTimer
    global GameState, SoundMuted

    if RL.IsKeyPressed(RL.KEY_M) {
        SoundMuted := !SoundMuted
    }

    if GameState == STATE_TITLE {
        if RL.IsKeyPressed(RL.KEY_SPACE) || RL.IsKeyPressed(RL.KEY_ENTER) || RL.IsMouseButtonPressed(0) {
            ResetGame()
        }
        return
    }

    if GameState == STATE_GAMEOVER {
        if RL.IsKeyPressed(RL.KEY_R) || RL.IsKeyPressed(RL.KEY_SPACE) || RL.IsKeyPressed(RL.KEY_ENTER) {
            ResetGame()
        }
        return
    }

    if RL.IsKeyPressed(RL.KEY_P) {
        GameState := (GameState == STATE_PAUSED) ? STATE_PLAYING : STATE_PAUSED
        return
    }

    if RL.IsKeyPressed(RL.KEY_R) {
        ResetGame()
        return
    }

    if GameState != STATE_PLAYING
        return

    ; Base vertical & horizontal speeds
    speed := (SugarRushTimer > 0) ? 440.0 : 280.0
    targetVx := 0.0
    targetVy := 0.0

    if RL.IsKeyDown(RL.KEY_W) || RL.IsKeyDown(RL.KEY_UP)
        targetVy -= speed
    if RL.IsKeyDown(RL.KEY_S) || RL.IsKeyDown(RL.KEY_DOWN)
        targetVy += speed
    if RL.IsKeyDown(RL.KEY_A) || RL.IsKeyDown(RL.KEY_LEFT)
        targetVx -= speed * 0.7
    if RL.IsKeyDown(RL.KEY_D) || RL.IsKeyDown(RL.KEY_RIGHT)
        targetVx += speed * 0.9

    ; If not holding horizontal keys and not dashing, smoothly cruise toward base position (X = 130)
    if !RL.IsKeyDown(RL.KEY_A) && !RL.IsKeyDown(RL.KEY_LEFT) && !RL.IsKeyDown(RL.KEY_D) && !RL.IsKeyDown(RL.KEY_RIGHT) && DashTimer <= 0 {
        targetVx := (130.0 - PlayerX) * 1.8
    }

    ; Mouse steering assistance
    if RL.IsMouseButtonDown(0) {
        my := RL.GetMouseY()
        diffY := my - (PlayerY + PlayerH / 2)
        if Abs(diffY) > 8
            targetVy := (diffY > 0 ? 1 : -1) * Min(speed, Abs(diffY) * 7)
    }

    ; --- Spacebar / Right-Click: ROCKET DASH ---
    if (RL.IsKeyPressed(RL.KEY_SPACE) || RL.IsMouseButtonPressed(1)) && DashCooldown <= 0 {
        DashTimer := 0.38
        DashCooldown := 1.0

        hasCaff := PlayerCaffeine >= 10.0
        if hasCaff
            PlayerCaffeine := Max(0.0, PlayerCaffeine - 10.0)

        boostSpeed := hasCaff ? 750.0 : 540.0
        PlayerVx := boostSpeed
        PlayAudio(SndDash)
        ShakeTimer := 0.12

        dashTxt := hasCaff ? "SUPER DASH!" : "ROCKET BOOST!"
        AddFloatingText(dashTxt, PlayerX + PlayerW, PlayerY - 10, hasCaff ? 0x00FFFFFF : 0xFFD700FF)

        shouts := hasCaff ? ["HOLD ONTO YOUR HATS!", "TURBO CHUB SPEED!", "SPEED OF SOUND, BABY!"] : ["WHOOSH!", "OUTTA MY WAY!", "BROOM GO BRRR!"]
        SayWitch(shouts[RL.GetRandomValue(1, shouts.Length)], 3, 1.8, true)

        Loop 16 {
            pCol := hasCaff ? 0x00FFFFFF : 0xF5CD2FFF
            AddParticle(PlayerX + 10, PlayerY + PlayerH * 0.7, RL.GetRandomValue(-220, -80), RL.GetRandomValue(-60, 60), pCol, 5, 0.45)
        }
    }

    ; While dashing, lock forward propulsion
    if DashTimer > 0 {
        PlayerVx := Max(PlayerVx, 600.0)
    } else {
        PlayerVx += (targetVx - PlayerVx) * 10.0 * dt
    }
    PlayerVy += (targetVy - PlayerVy) * 12.0 * dt
}

; ==============================================================================
; GAME LOGIC STEP
; ==============================================================================
UpdateGame(dt) {
    global PlayerX, PlayerY, PlayerVx, PlayerVy, PlayerAngle, PlayerHealth, PlayerCaffeine
    global SugarRushTimer, InvulnTimer, DashTimer, DashCooldown, Score, Calories, Combo, ComboTimer
    global TotalJunkEaten, TotalDrinksChugged, TotalVegSmashed, DifficultySpeed, HighScore
    global WitchAnimTick, ShakeTimer, ItemSpawnTimer, EnemySpawnTimer, GameState
    global Items, Enemies, Particles, FloatingTexts, Stars, CurrentBubble, IdleSpeechTimer
    global ConsecutiveCans, BoringStories

    if GameState != STATE_PLAYING
        return

    ; Difficulty scales gently with score
    DifficultySpeed := 1.0 + Min(1.2, Score / 5000.0)

    ; Speech bubble countdown
    if CurrentBubble.timer > 0 {
        CurrentBubble.timer -= dt
    }

    ; Idle rambling timer
    IdleSpeechTimer += dt
    if IdleSpeechTimer >= 7.5 && CurrentBubble.timer <= 0 {
        IdleSpeechTimer := 0.0
        rIdx := RL.GetRandomValue(1, BoringStories.Length)
        SayWitch(BoringStories[rIdx], 1, 3.2, false)
    }

    ; Caffeine burn rate
    if SugarRushTimer > 0 {
        SugarRushTimer -= dt
        PlayerCaffeine := (SugarRushTimer / 5.0) * 100.0
        if SugarRushTimer <= 0 {
            PlayerCaffeine := 20.0
            AddFloatingText("SUGAR CRASH!", PlayerX, PlayerY - 20, 0xFFA100FF)
            SayWitch("UH OH... CRASHING HARD...", 3, 2.0)
        }
    } else {
        PlayerCaffeine := Max(0.0, PlayerCaffeine - 1.8 * dt)
    }

    ; Dash & Invulnerability cooldowns
    if DashTimer > 0
        DashTimer -= dt
    if DashCooldown > 0
        DashCooldown -= dt
    if InvulnTimer > 0
        InvulnTimer -= dt
    if ShakeTimer > 0
        ShakeTimer -= dt

    ; Combo timer
    if ComboTimer > 0 {
        ComboTimer -= dt
        if ComboTimer <= 0 {
            Combo := 1
            ConsecutiveCans := 0
        }
    }

    ; Move Player
    PlayerX += PlayerVx * dt
    PlayerY += PlayerVy * dt

    ; Clamp to screen boundaries
    PlayerX := Max(10.0, Min(ScreenWidth - PlayerW - 20.0, PlayerX))
    PlayerY := Max(20.0, Min(ScreenHeight - PlayerH - 45.0, PlayerY))

    ; Broom tilt angle
    targetAngle := (PlayerVy / 300.0) * 14.0
    if DashTimer > 0 || SugarRushTimer > 0
        targetAngle += 4.0
    PlayerAngle += (targetAngle - PlayerAngle) * 8.0 * dt

    ; Witch animation tick
    WitchAnimTick += dt * (SugarRushTimer > 0 ? 12.0 : 6.0)

    ; Broom exhaust particles
    broomTailX := PlayerX + 15
    broomTailY := PlayerY + PlayerH * 0.72
    exhaustColor := (SugarRushTimer > 0) ? 0xFFEE00FF : ((DashTimer > 0) ? 0x00E5FFFF : 0x9B59D4FF)
    AddParticle(broomTailX, broomTailY, RL.GetRandomValue(-120, -50), RL.GetRandomValue(-25, 25), exhaustColor, RL.GetRandomValue(3, 5), 0.35)
    if SugarRushTimer > 0 {
        AddParticle(broomTailX + RL.GetRandomValue(-5, 5), broomTailY + RL.GetRandomValue(-8, 8), RL.GetRandomValue(-150, -60), RL.GetRandomValue(-40, 40), 0xFF69B4FF, 4, 0.45)
    }

    ; Spawn Items
    ItemSpawnTimer += dt
    if ItemSpawnTimer >= (1.1 / DifficultySpeed) {
        ItemSpawnTimer := 0.0
        SpawnRandomItem()
    }

    ; Spawn Enemies
    EnemySpawnTimer += dt
    if EnemySpawnTimer >= (1.25 / DifficultySpeed) {
        EnemySpawnTimer := 0.0
        SpawnRandomEnemy()
    }

    ; --- Update Items ---
    i := Items.Length
    while i >= 1 {
        item := Items[i]
        item.x += item.vx * dt
        item.y += Sin(A_TickCount / 220.0 + item.bobOffset) * 0.7

        hit := RL.CheckCollisionRecs(
            PlayerX + 16, PlayerY + 12, PlayerW - 32, PlayerH - 24,
            item.x + 4, item.y + 4, item.w - 8, item.h - 8
        )

        if hit {
            Score += item.pts * Combo
            Calories += item.cal
            ComboTimer := 2.5
            Combo := Min(5, Combo + 1)
            TotalJunkEaten++
            IdleSpeechTimer := 0.0  ; Reset idle chatter timer

            if item.type == "energy" || item.type == "soda" {
                TotalDrinksChugged++
                ConsecutiveCans++
                PlayAudio(SndDrink)

                ; Cartoon Tooltip speech for can strikes / streaks!
                if ConsecutiveCans >= 3 {
                    SayWitch("MAXIMUM OVERDRIVE! GIVE ME MORE SODAAA!", 4, 2.2, true)
                } else if item.type == "energy" {
                    caffLines := [
                        "HELL YEAH, I LOVE CAFFEINE!",
                        "MY HEART IS VIBRATING AT 4000 RPM!",
                        "LIQUID ELECTRICITY, BABY!",
                        "TASTES LIKE SWEET CHEMICALS!"
                    ]
                    SayWitch(caffLines[RL.GetRandomValue(1, caffLines.Length)], 3, 2.0, true)
                } else {
                    sodaLines := [
                        "MMMM, UNHEALTHY FOOOD!",
                        "SWEET CARBONATED HEAVEN!",
                        "NOTHING BEATS CORN SYRUP!"
                    ]
                    SayWitch(sodaLines[RL.GetRandomValue(1, sodaLines.Length)], 2, 2.0, true)
                }
            } else {
                PlayAudio(SndCrunch)
                foodLines := [
                    "MMMM, UNHEALTHY FOOOD!",
                    "GREASE IS THE GREATEST SPICE!",
                    "PURE CHEESY PERFECTION!",
                    "SUGAR, FAT, AND GLORY!"
                ]
                SayWitch(foodLines[RL.GetRandomValue(1, foodLines.Length)], 2, 1.8, false)
            }

            if item.type == "pizza" && PlayerHealth < PlayerMaxHealth {
                PlayerHealth++
                AddFloatingText("+1 HEART!", PlayerX + 20, PlayerY - 10, 0xFF4D6DFF)
                SayWitch("PIZZA HEALS MY TIRED SOUL!", 3, 1.8, true)
            }

            ; Caffeine increase
            if SugarRushTimer <= 0 {
                PlayerCaffeine := Min(100.0, PlayerCaffeine + item.caff)
                if PlayerCaffeine >= 100.0 {
                    SugarRushTimer := 5.0
                    PlayAudio(SndRush)
                    AddFloatingText("!!! SUGAR RUSH !!!", PlayerX - 30, PlayerY - 30, 0x39FF14FF)
                    SayWitch("SUGAR RUSH ENGAGED! OUT OF MY WAY!", 4, 2.5, true)
                    ShakeTimer := 0.25
                }
            }

            txt := "+" . (item.pts * Combo) . " (" . item.name . ")"
            AddFloatingText(txt, item.x, item.y - 10, (item.type == "energy" ? 0x39FF14FF : 0xFFCB00FF))
            Loop 8 {
                AddParticle(item.x + item.w/2, item.y + item.h/2, RL.GetRandomValue(-100, 100), RL.GetRandomValue(-100, 100), 0xFFEE00FF, 3, 0.4)
            }

            Items.RemoveAt(i)
        } else if item.x < -item.w {
            Items.RemoveAt(i)
        }
        i--
    }

    ; --- Update Enemies ---
    i := Enemies.Length
    while i >= 1 {
        en := Enemies[i]
        en.tick += dt * 3.5
        en.x += en.vx * dt

        if en.pattern == "wave" {
            en.y := en.startY + Sin(en.tick) * 55.0
        } else if en.pattern == "arc" {
            en.y := en.startY + Cos(en.tick * 0.7) * 35.0
        } else if en.pattern == "drift" {
            en.y := en.startY + Sin(en.tick * 0.5) * 20.0
        }

        hit := RL.CheckCollisionRecs(
            PlayerX + 16, PlayerY + 12, PlayerW - 32, PlayerH - 24,
            en.x + 6, en.y + 6, en.w - 12, en.h - 12
        )

        if hit {
            IdleSpeechTimer := 0.0
            if SugarRushTimer > 0 || DashTimer > 0 {
                ; Smashed enemy in Sugar Rush / Dash!
                Score += 250 * Combo
                TotalVegSmashed++
                PlayAudio(SndCrunch)
                AddFloatingText("SUGAR CRUSH! +250", en.x, en.y - 15, 0x00FFFFFF)
                ShakeTimer := 0.15

                smashLines := [
                    "TAKE THAT, CELLULOSE!",
                    "BEGONE, GREEN FIEND!",
                    "VITAMINS CANNOT STOP ME!",
                    "NOT IN MY DIET!",
                    "CRUSHED LIKE RAW KALE!"
                ]
                SayWitch(smashLines[RL.GetRandomValue(1, smashLines.Length)], 4, 1.9, true)

                Loop 14 {
                    AddParticle(en.x + en.w/2, en.y + en.h/2, RL.GetRandomValue(-150, 150), RL.GetRandomValue(-150, 150), 0x38B000FF, 4, 0.5)
                }
                Enemies.RemoveAt(i)
            } else if InvulnTimer <= 0 {
                ; Witch takes damage from healthy food
                PlayerHealth--
                Combo := 1
                ComboTimer := 0.0
                ConsecutiveCans := 0
                InvulnTimer := 1.2
                ShakeTimer := 0.3
                PlayAudio(SndHurt)

                insults := [
                    "BLEHHH! FIBER OVERDOSE!",
                    "WHY DOES IT TASTE LIKE LAWN TRIMMINGS?!",
                    "CALL A HAG, IT'S PURE TAP WATER!",
                    "MY CHOLESTEROL IS DROPPING!",
                    "EW, VEGETABLES! DISGUSTING!"
                ]
                chosenInsult := insults[RL.GetRandomValue(1, insults.Length)]
                AddFloatingText(chosenInsult, PlayerX, PlayerY - 20, 0xFF3333FF)
                SayWitch(chosenInsult, 4, 2.2, true)

                if PlayerHealth <= 0 {
                    GameState := STATE_GAMEOVER
                    PlayAudio(SndGameOver)
                    SayWitch("I HAVE BEEN DETOXED... GOODBYE CRUEL WORLD...", 5, 4.0, true)
                    if Score > HighScore
                        HighScore := Score
                }
                Enemies.RemoveAt(i)
            }
        } else if en.x < -en.w {
            Enemies.RemoveAt(i)
        }
        i--
    }

    ; Update Particles
    i := Particles.Length
    while i >= 1 {
        p := Particles[i]
        p.life -= dt
        if p.life <= 0 {
            Particles.RemoveAt(i)
        } else {
            p.x += p.vx * dt
            p.y += p.vy * dt
        }
        i--
    }

    ; Update Floating Texts
    i := FloatingTexts.Length
    while i >= 1 {
        ft := FloatingTexts[i]
        ft.life -= dt
        if ft.life <= 0 {
            FloatingTexts.RemoveAt(i)
        } else {
            ft.x += ft.vx * dt
            ft.y += ft.vy * dt
        }
        i--
    }

    ; Update Background Stars
    starSpeedMul := (SugarRushTimer > 0) ? 2.5 : 1.0
    for s in Stars {
        s.x -= s.speed * starSpeedMul * 20.0 * dt
        if s.x < 0 {
            s.x := ScreenWidth + 5
            s.y := RL.GetRandomValue(0, ScreenHeight - 90)
        }
    }
}

; ==============================================================================
; RENDERING
; ==============================================================================
Render() {
    global PlayerX, PlayerY, PlayerW, PlayerH, PlayerAngle, PlayerHealth, PlayerMaxHealth
    global PlayerCaffeine, SugarRushTimer, InvulnTimer, DashTimer, DashCooldown, Score, Calories, Combo
    global HighScore, TotalJunkEaten, TotalDrinksChugged, TotalVegSmashed, GameState
    global Items, Enemies, Particles, FloatingTexts, Stars, ShakeTimer, WitchAnimTick
    global TexWitch1, TexWitch2, TexHeart, TexHeartEmpty, CurrentBubble

    RL.BeginDrawing()

    shakeX := 0.0, shakeY := 0.0
    if ShakeTimer > 0 {
        shakeX := RL.GetRandomValue(-4, 4)
        shakeY := RL.GetRandomValue(-4, 4)
    }

    ; Background gradient
    RL.ClearBackground(0x130F26FF)
    RL.DrawRectangleGradientV(0, 0, ScreenWidth, ScreenHeight, 0x110A24FF, 0x2A1B4EFF)

    ; Distant Moon
    RL.DrawCircle(ScreenWidth - 140 + shakeX, 90 + shakeY, 44, 0xFFEAA722)
    RL.DrawCircle(ScreenWidth - 140 + shakeX, 90 + shakeY, 38, 0xFFEAA7FF)
    RL.DrawCircle(ScreenWidth - 126 + shakeX, 82 + shakeY, 34, 0x1A1236FF)

    ; Stars
    for s in Stars {
        RL.DrawPixel(s.x + shakeX, s.y + shakeY, RL.ColorAlpha(RL.WHITE, s.alpha / 255.0))
        if s.size > 1
            RL.DrawRectangle(s.x + shakeX, s.y + shakeY, s.size, s.size, RL.ColorAlpha(0xFFF3B0FF, s.alpha / 255.0))
    }

    ; Mountain silhouettes
    RL.DrawTriangle(-50 + shakeX, ScreenHeight - 60, 180 + shakeX, ScreenHeight - 210, 410 + shakeX, ScreenHeight - 60, 0x1E1538FF)
    RL.DrawTriangle(290 + shakeX, ScreenHeight - 60, 540 + shakeX, ScreenHeight - 240, 790 + shakeX, ScreenHeight - 60, 0x221840FF)
    RL.DrawTriangle(660 + shakeX, ScreenHeight - 60, 860 + shakeX, ScreenHeight - 190, 1060 + shakeX, ScreenHeight - 60, 0x1E1538FF)

    ; Ground skyline
    RL.DrawRectangle(0, ScreenHeight - 60, ScreenWidth, 60, 0x140E26FF)
    Loop 18 {
        rx := (A_Index - 1) * 56 + shakeX
        RL.DrawRectangle(rx, ScreenHeight - 78, 44, 18, 0x140E26FF)
        RL.DrawTriangle(rx - 6, ScreenHeight - 78, rx + 22, ScreenHeight - 108, rx + 50, ScreenHeight - 78, 0x140E26FF)
    }

    ; Particles
    for p in Particles {
        alpha := p.life / p.maxLife
        RL.DrawRectangle(p.x + shakeX, p.y + shakeY, p.size, p.size, RL.ColorAlpha(p.color, alpha))
    }

    ; Items
    for it in Items {
        RL.DrawTexturePro(it.tex.tex, 0, 0, it.tex.w, it.tex.h, it.x + shakeX, it.y + shakeY, it.w, it.h, 0, 0, 0, RL.WHITE)
    }

    ; Enemies
    for en in Enemies {
        RL.DrawTexturePro(en.tex.tex, 0, 0, en.tex.w, en.tex.h, en.x + shakeX, en.y + shakeY, en.w, en.h, 0, 0, 0, RL.WHITE)
    }

    ; Witch Player
    if GameState == STATE_PLAYING || GameState == STATE_PAUSED {
        drawWitch := true
        if InvulnTimer > 0 && Mod(Integer(InvulnTimer * 20), 2) == 0
            drawWitch := false

        if drawWitch {
            activeTex := (Mod(Integer(WitchAnimTick), 2) == 0) ? TexWitch1 : TexWitch2

            if SugarRushTimer > 0 {
                RL.DrawCircleGradient(
                    PlayerX + PlayerW / 2 + shakeX, PlayerY + PlayerH / 2 + shakeY,
                    PlayerW * 0.75, 0x39FF1444, 0x00000000
                )
            }

            tint := (InvulnTimer > 0) ? 0xFF9999FF : ((SugarRushTimer > 0) ? 0xFFFFAAFF : RL.WHITE)
            RL.DrawTexturePro(
                activeTex.tex,
                0, 0, activeTex.w, activeTex.h,
                PlayerX + PlayerW / 2 + shakeX, PlayerY + PlayerH / 2 + shakeY,
                PlayerW, PlayerH,
                PlayerW / 2, PlayerH / 2,
                PlayerAngle,
                tint
            )
        }

        ; Dialogue text above her head (no tooltip box)
        if CurrentBubble.timer > 0 {
            headX := PlayerX + PlayerW * 0.5 + shakeX
            headY := PlayerY + shakeY
            DrawWitchSpeech(CurrentBubble.text, headX, headY, CurrentBubble.isHigh)
        }
    }

    ; Floating comic texts
    for ft in FloatingTexts {
        alpha := ft.life / ft.maxLife
        RL.DrawText(ft.text, ft.x + shakeX, ft.y + shakeY, 16, RL.ColorAlpha(ft.color, alpha))
    }

    ; Sugar Rush Screen Border Aura
    if SugarRushTimer > 0 {
        borderThick := 6
        glowCol := (Mod(Integer(A_TickCount / 80), 2) == 0) ? 0x39FF14FF : 0xFF00FFFF
        RL.DrawRectangleLinesEx(0, 0, ScreenWidth, ScreenHeight, borderThick, glowCol)
    }

    ; ==========================================================================
    ; HUD DISPLAY
    ; ==========================================================================
    RL.DrawRectangle(0, 0, ScreenWidth, 48, 0x0A0614CC)
    RL.DrawLine(0, 48, ScreenWidth, 48, 0x3D2B66FF)

    ; 1. Health (Pixel Hearts)
    RL.DrawText("STAMINA:", 16, 15, 18, 0xBDD788FF)
    Loop PlayerMaxHealth {
        hx := 105 + (A_Index - 1) * 26
        hTex := (A_Index <= PlayerHealth) ? TexHeart : TexHeartEmpty
        RL.DrawTexturePro(
            hTex.tex,
            0, 0, hTex.w, hTex.h,
            hx, 13, hTex.w * 3, hTex.h * 3,
            0, 0, 0, RL.WHITE
        )
    }

    ; 2. Caffeine / Sugar Rush Bar
    caffBarX := 210, caffBarY := 14, caffBarW := 190, caffBarH := 20
    RL.DrawText("CAFFEINE:", caffBarX, 15, 16, 0xFFEA00FF)
    barInnerX := caffBarX + 85
    RL.DrawRectangle(barInnerX, caffBarY, caffBarW, caffBarH, 0x221A38FF)
    fillW := (PlayerCaffeine / 100.0) * (caffBarW - 4)
    barColor := (SugarRushTimer > 0) ? 0x39FF14FF : ((PlayerCaffeine >= 75) ? 0xFFD000FF : 0x00E5FFFF)
    RL.DrawRectangle(barInnerX + 2, caffBarY + 2, fillW, caffBarH - 4, barColor)
    RL.DrawRectangleLines(barInnerX, caffBarY, caffBarW, caffBarH, 0xD0D7DEFF)

    if SugarRushTimer > 0 {
        RL.DrawText("!! SUGAR RUSH !!", barInnerX + 32, caffBarY + 3, 14, 0x000000FF)
    } else {
        RL.DrawText(Round(PlayerCaffeine) . "%", barInnerX + caffBarW / 2 - 12, caffBarY + 3, 14, RL.WHITE)
    }

    ; 3. Calories Counter
    RL.DrawText("CALORIES:", 520, 15, 16, 0xFFA100FF)
    RL.DrawText(Calories . " kcal", 615, 13, 20, RL.GOLD)

    ; 4. Score & Combo
    RL.DrawText("SCORE: " . Score, 760, 13, 20, RL.WHITE)
    if Combo > 1 {
        comboCol := (Combo >= 5) ? 0xFF0055FF : 0x39FF14FF
        RL.DrawText(Combo . "x COMBO!", 760, 31, 14, comboCol)
    }

    ; Bottom Controls Guide & Live Dash Indicator
    RL.DrawRectangle(0, ScreenHeight - 28, ScreenWidth, 28, 0x0A0614EE)
    RL.DrawLine(0, ScreenHeight - 28, ScreenWidth, ScreenHeight - 28, 0x2A1B4EFF)
    RL.DrawText("[W,A,S,D / Mouse] Fly", 20, ScreenHeight - 21, 14, 0xBDD788FF)

    ; Dynamic Dash Status Indicator
    dashText := ""
    dashCol := 0x39FF14FF
    if DashTimer > 0 {
        dashText := ">>> [SPACE] DASHING! (INVINCIBLE BOOST) <<<"
        dashCol := 0x00E5FFFF
    } else if DashCooldown <= 0 {
        dashText := "[SPACE] DASH: >> READY << (ROCKET BOOST & SMASH HAZARDS)"
        dashCol := 0x39FF14FF
    } else {
        dashText := "[SPACE] DASH: RECHARGING (" . Round(DashCooldown, 1) . "s)"
        dashCol := 0xFFA100FF
    }
    RL.DrawText(dashText, 210, ScreenHeight - 21, 14, dashCol)

    RL.DrawText("[P] Pause   [M] Mute   [R] Restart", ScreenWidth - 250, ScreenHeight - 21, 14, 0x9B8FB8FF)

    ; ==========================================================================
    ; OVERLAY SCREENS
    ; ==========================================================================
    if GameState == STATE_TITLE {
        RL.DrawRectangle(0, 0, ScreenWidth, ScreenHeight, 0x0A0614DD)

        titleY := 80
        RL.DrawText("JUNK FOOD WITCH", ScreenWidth / 2 - 220, titleY, 46, 0xF5CD2FFF)
        RL.DrawText("BROOM RUSH", ScreenWidth / 2 - 130, titleY + 54, 38, 0x00E5FFFF)

        RL.DrawTexturePro(
            TexWitch1.tex,
            0, 0, TexWitch1.w, TexWitch1.h,
            ScreenWidth / 2 - (TexWitch1.w * 4) / 2, titleY + 115,
            TexWitch1.w * 4, TexWitch1.h * 4,
            0, 0, 0, RL.WHITE
        )

        RL.DrawText('"Dieting is for skinny amateurs."', ScreenWidth / 2 - 145, titleY + 225, 18, 0xBDD788FF)

        boxY := titleY + 260
        RL.DrawRectangle(ScreenWidth / 2 - 270, boxY, 540, 105, 0x1B1233DD)
        RL.DrawRectangleLines(ScreenWidth / 2 - 270, boxY, 540, 105, 0x6E399EFF)

        RL.DrawText("CHUG:  Energy Drinks, Soda, Pizza, Burgers, Donuts (+Points & Sugar Rush!)", ScreenWidth / 2 - 250, boxY + 16, 14, 0x39FF14FF)
        RL.DrawText("AVOID: Broccoli, Carrot Missiles, Smug Apples, Tap Water (-Stamina!)", ScreenWidth / 2 - 250, boxY + 44, 14, 0xFF5555FF)
        RL.DrawText("DASH:  Press [SPACE] to rocket-boost forward & smash hazards!", ScreenWidth / 2 - 250, boxY + 72, 14, 0x00E5FFFF)

        pulse := (Mod(Integer(A_TickCount / 500), 2) == 0)
        btnCol := pulse ? RL.WHITE : 0xF5CD2FFF
        RL.DrawText("PRESS [SPACE] OR [CLICK] TO FLY!", ScreenWidth / 2 - 180, boxY + 130, 22, btnCol)
    }

    if GameState == STATE_PAUSED {
        RL.DrawRectangle(0, 0, ScreenWidth, ScreenHeight, 0x0A0614AA)
        RL.DrawText("PAUSED", ScreenWidth / 2 - 70, ScreenHeight / 2 - 30, 40, RL.RAYWHITE)
        RL.DrawText("Press [P] to Resume or [R] to Restart", ScreenWidth / 2 - 150, ScreenHeight / 2 + 25, 18, 0xBDD788FF)
    }

    if GameState == STATE_GAMEOVER {
        RL.DrawRectangle(0, 0, ScreenWidth, ScreenHeight, 0x0A0614EE)

        RL.DrawText("VEGAN DETOX OVERDOSE!", ScreenWidth / 2 - 230, 80, 36, 0xFF3355FF)
        RL.DrawText("Bernice collapsed from accidental healthy nutrition.", ScreenWidth / 2 - 210, 126, 18, 0xBDD788FF)

        cardY := 165
        RL.DrawRectangle(ScreenWidth / 2 - 220, cardY, 440, 205, 0x1B1233DD)
        RL.DrawRectangleLines(ScreenWidth / 2 - 220, cardY, 440, 205, 0x6E399EFF)

        RL.DrawText("FINAL SCORE: " . Score, ScreenWidth / 2 - 180, cardY + 20, 22, RL.GOLD)
        RL.DrawText("HIGH SCORE:  " . HighScore, ScreenWidth / 2 - 180, cardY + 52, 18, RL.RAYWHITE)
        RL.DrawText("Calories Ingested: " . Calories . " kcal", ScreenWidth / 2 - 180, cardY + 84, 16, 0xFFA100FF)
        RL.DrawText("Energy Drinks & Sodas: " . TotalDrinksChugged, ScreenWidth / 2 - 180, cardY + 108, 16, 0x00E5FFFF)
        RL.DrawText("Vegetables Smashed: " . TotalVegSmashed, ScreenWidth / 2 - 180, cardY + 132, 16, 0x39FF14FF)

        rankTitle := "Salad Novice"
        if Score >= 15000
            rankTitle := "Grand Arch-Goblin of the Deep Fryer"
        else if Score >= 8000
            rankTitle := "Soda Sorceress (Broom Overloaded)"
        else if Score >= 4000
            rankTitle := "Caffeine Adept (High Fructose Flyer)"
        else if Score >= 1500
            rankTitle := "Snack Enthusiast (Couch Potato)"

        RL.DrawText("WITCH RANK: " . rankTitle, ScreenWidth / 2 - 180, cardY + 165, 16, 0xF5CD2FFF)

        pulse := (Mod(Integer(A_TickCount / 500), 2) == 0)
        btnColor := pulse ? RL.WHITE : 0x39FF14FF
        RL.DrawText("PRESS [R] OR [SPACE] TO FLY AGAIN!", ScreenWidth / 2 - 190, cardY + 230, 22, btnColor)
    }

    RL.EndDrawing()
}

; ==============================================================================
; MAIN GAME LOOP
; ==============================================================================
StartTick := A_TickCount
ShootFrameDone := false

while !RL.WindowShouldClose() {
    dt := RL.GetFrameTime()
    if dt > 0.05
        dt := 0.05

    ; Stream background music
    if AudioReady && BgmStream && RL.IsMusicValid(BgmStream) {
        if SoundMuted {
            RL.SetMusicVolume(BgmStream, 0.0)
        } else {
            curPitch := (SugarRushTimer > 0) ? 1.22 : 1.0
            RL.SetMusicPitch(BgmStream, curPitch)
            RL.SetMusicVolume(BgmStream, 0.38)
        }
        RL.UpdateMusicStream(BgmStream)
    }

    HandleInput(dt)
    UpdateGame(dt)
    Render()

    ; Headless screenshot capture
    if ShotPath != "" && !ShootFrameDone && (AutoExit && A_TickCount - StartTick >= (AutoExit / 2)) {
        Render()
        RL.ScreenShot(ShotPath)
        ShootFrameDone := true
    }

    if AutoExit && (A_TickCount - StartTick >= AutoExit)
        break
}

; ==============================================================================
; CLEANUP
; ==============================================================================
RL.UnloadTexture(TexWitch1.tex)
RL.UnloadTexture(TexWitch2.tex)
RL.UnloadTexture(TexEnergy.tex)
RL.UnloadTexture(TexSoda.tex)
RL.UnloadTexture(TexPizza.tex)
RL.UnloadTexture(TexDonut.tex)
RL.UnloadTexture(TexBurger.tex)
RL.UnloadTexture(TexBroccoli.tex)
RL.UnloadTexture(TexCarrot.tex)
RL.UnloadTexture(TexWater.tex)
RL.UnloadTexture(TexApple.tex)
RL.UnloadTexture(TexHeart.tex)
RL.UnloadTexture(TexHeartEmpty.tex)

if AudioReady {
    if BgmStream && RL.IsMusicValid(BgmStream)
        RL.UnloadMusicStream(BgmStream)
    if SndDrink
        RL.UnloadSound(SndDrink)
    if SndCrunch
        RL.UnloadSound(SndCrunch)
    if SndHurt
        RL.UnloadSound(SndHurt)
    if SndRush
        RL.UnloadSound(SndRush)
    if SndDash
        RL.UnloadSound(SndDash)
    if SndGameOver
        RL.UnloadSound(SndGameOver)
    RL.CloseAudioDevice()
}

RL.CloseWindow()
ExitApp(0)
