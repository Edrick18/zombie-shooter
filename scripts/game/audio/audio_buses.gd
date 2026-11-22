extends RefCounted
## Modul: Ton (scripts/game/audio).
## Die Busse des Spiels und ihre Effekte. Nur statische Funktionen und Werte, einbinden mit preload.
##
##   Master   [Begrenzer]                 alles zusammen, Regler "Lautstärke"
##   ├─ Sfx                               Geräusche ohne Raum (Menü, Fanfaren, Treffer), Regler "Geräusche"
##   │   └─ Reverb   [Nachhall]           Geräusche im Studio: alles mit Ort in der Welt, dazu Schüsse
##   │                                    und Schritte des Spielers. Geht in Sfx, der Regler gilt also mit
##   └─ Music    [Tiefpass]               Musik, Regler "Musik". Der Tiefpass ist nur an, wenn die
##                                        Musik dumpf sein soll (Pause, Kistenwahl, Rucksack)
##
## ensure() legt an, was fehlt, und lässt alles andere stehen: Es darf beliebig oft laufen (jeder
## Neustart der Szene, jede Änderung an den Einstellungen). Die Lautstärken der Busse setzt
## Settings.apply_audio, das Zurückdrängen und Dämpfen der Musik macht music.gd.
##
## Die Werte hier sind nach Zahlen gewählt und zum Nachstellen gedacht:
##   Begrenzer: Decke -1 dBFS. Dauerfeuer aus zwei Waffen mit einer Explosion darüber kann ohne ihn
##     über 0 dBFS kommen (siehe tools/check_mix.py). Er greift nur bei solchen Spitzen ein.
##   Nachhall: kleiner Saal, kurz und dezent (ein Fernsehstudio ist gedämpft). Mehr Raum: REVERB_WET
##     und REVERB_ROOM_SIZE erhöhen. Dumpfer: REVERB_DAMPING erhöhen.

const MASTER: String = "Master"
const SFX: String = "Sfx"
const REVERB: String = "Reverb"
const MUSIC: String = "Music"

## Begrenzer auf dem Master: Decke in dBFS, Vorverstärkung in dB, Erholzeit in Sekunden.
const LIMITER_CEILING_DB: float = -1.0
const LIMITER_PRE_GAIN_DB: float = 0.0
const LIMITER_RELEASE: float = 0.1

## Nachhall des Studios. room_size 0 bis 1 (Länge des Halls), damping 0 bis 1 (wie schnell die
## Höhen verschwinden), spread 0 bis 1 (Breite), hipass 0 bis 1 (nimmt dem Hall die Tiefen, damit
## Schüsse und Explosionen nicht dröhnen), dry und wet 0 bis 1 (Anteil Original und Hall),
## predelay in Millisekunden (Abstand bis zum ersten Rückwurf).
const REVERB_ROOM_SIZE: float = 0.45
const REVERB_DAMPING: float = 0.6
const REVERB_SPREAD: float = 0.8
const REVERB_HIPASS: float = 0.25
const REVERB_DRY: float = 1.0
const REVERB_WET: float = 0.16
const REVERB_PREDELAY_MSEC: float = 25.0
const REVERB_PREDELAY_FEEDBACK: float = 0.2

## Tiefpass der Musik: Ab dieser Grenzfrequenz gilt er als offen und wird abgeschaltet.
const MUSIC_OPEN_CUTOFF: float = 20000.0


## Legt die Busse und ihre Effekte an, wenn es sie noch nicht gibt.
static func ensure() -> void:
	_ensure_bus(SFX, MASTER)
	_ensure_bus(REVERB, SFX)
	_ensure_bus(MUSIC, MASTER)
	var master: int = AudioServer.get_bus_index(MASTER)
	if limiter() == null and master != -1:
		var hard: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		hard.ceiling_db = LIMITER_CEILING_DB
		hard.pre_gain_db = LIMITER_PRE_GAIN_DB
		hard.release = LIMITER_RELEASE
		AudioServer.add_bus_effect(master, hard)
	var room_bus: int = AudioServer.get_bus_index(REVERB)
	if reverb() == null and room_bus != -1:
		var room: AudioEffectReverb = AudioEffectReverb.new()
		room.room_size = REVERB_ROOM_SIZE
		room.damping = REVERB_DAMPING
		room.spread = REVERB_SPREAD
		room.hipass = REVERB_HIPASS
		room.dry = REVERB_DRY
		room.wet = REVERB_WET
		room.predelay_msec = REVERB_PREDELAY_MSEC
		room.predelay_feedback = REVERB_PREDELAY_FEEDBACK
		AudioServer.add_bus_effect(room_bus, room)
	var music_bus: int = AudioServer.get_bus_index(MUSIC)
	if music_filter() == null and music_bus != -1:
		var filter: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		filter.cutoff_hz = MUSIC_OPEN_CUTOFF
		AudioServer.add_bus_effect(music_bus, filter)
		AudioServer.set_bus_effect_enabled(music_bus, AudioServer.get_bus_effect_count(music_bus) - 1, false)


## Der Begrenzer auf dem Master, null wenn es ihn (noch) nicht gibt.
static func limiter() -> AudioEffectHardLimiter:
	var index: int = _effect_index(MASTER, "AudioEffectHardLimiter")
	if index == -1:
		return null
	return AudioServer.get_bus_effect(AudioServer.get_bus_index(MASTER), index) as AudioEffectHardLimiter


## Der Nachhall auf dem Bus Reverb, null wenn es ihn (noch) nicht gibt.
static func reverb() -> AudioEffectReverb:
	var index: int = _effect_index(REVERB, "AudioEffectReverb")
	if index == -1:
		return null
	return AudioServer.get_bus_effect(AudioServer.get_bus_index(REVERB), index) as AudioEffectReverb


## Der Tiefpass auf dem Bus Music, null wenn es ihn (noch) nicht gibt.
static func music_filter() -> AudioEffectLowPassFilter:
	var index: int = _effect_index(MUSIC, "AudioEffectLowPassFilter")
	if index == -1:
		return null
	return AudioServer.get_bus_effect(AudioServer.get_bus_index(MUSIC), index) as AudioEffectLowPassFilter


## Ist der Tiefpass der Musik gerade eingeschaltet?
static func is_music_filter_on() -> bool:
	var index: int = _effect_index(MUSIC, "AudioEffectLowPassFilter")
	return index != -1 and AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(MUSIC), index)


## Stellt den Tiefpass der Musik auf diese Grenzfrequenz. Ab MUSIC_OPEN_CUTOFF wird er
## abgeschaltet: Die Musik läuft dann unverändert durch.
static func set_music_cutoff(cutoff_hz: float) -> void:
	var index: int = _effect_index(MUSIC, "AudioEffectLowPassFilter")
	if index == -1:
		return
	var bus: int = AudioServer.get_bus_index(MUSIC)
	var filter: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bus, index) as AudioEffectLowPassFilter
	var open: bool = cutoff_hz >= MUSIC_OPEN_CUTOFF
	filter.cutoff_hz = minf(cutoff_hz, MUSIC_OPEN_CUTOFF)
	if AudioServer.is_bus_effect_enabled(bus, index) == open:
		AudioServer.set_bus_effect_enabled(bus, index, not open)


## Setzt die Lautstärke eines Busses aus einem Wert von 0 bis 1 (bei 0 ist er stumm geschaltet).
static func set_bus_level(bus_name: String, level: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return
	var silent: bool = level <= 0.0
	AudioServer.set_bus_mute(bus, silent)
	if not silent:
		AudioServer.set_bus_volume_db(bus, linear_to_db(level))


static func _ensure_bus(bus_name: String, send_to: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send_to)


## Stelle des ersten Effekts dieser Klasse auf dem Bus, -1 wenn es keinen gibt.
static func _effect_index(bus_name: String, effect_class: String) -> int:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus == -1:
		return -1
	for i: int in AudioServer.get_bus_effect_count(bus):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if effect != null and effect.is_class(effect_class):
			return i
	return -1
