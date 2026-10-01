#!/usr/bin/env python3
"""Benennt die deutschen Bezeichner in englische um.

Ersetzt nur im Code, nicht in Kommentaren oder Zeichenketten — die deutschen
Kommentare bleiben erhalten. Innerhalb von Kommentaren werden lediglich
Bezeichner in `Rückwärtsstrichen` mitgezogen, damit die Doku stimmig bleibt.
"""
import re, sys, glob, unicodedata

MAP = {
# --- Typen -------------------------------------------------------------
"Befehlskatalog": "CommandCatalog", "Befehl": "Command",
"Lautstärkelesart": "VolumeEncoding", "MIDIWirkung": "MIDIEffect",
"TempoSonderfall": "TempoSpecial", "Zelle": "Cell",
"Fundstelle": "SourceLocation", "Warnung": "Warning", "Hinweis": "Notice",
"Diagnose": "Diagnostics", "Notenanalyse": "NoteAnalysis",
"Notenbefund": "NoteFinding", "Klingend": "SoundingNote",
"Playsequenz": "PlaySequence", "GeladenerSong": "LoadedSong",
"PatternDarstellung": "PatternRendering", "PatternAnsicht": "PatternView",
"SonginfoAnsicht": "SongInfoView", "Hauptansicht": "MainView",
"Optionen": "Options", "Testmaterial": "TestFiles", "Modul": "Module",
"Art": "Kind",
# --- MEDError ----------------------------------------------------------
"zuKurz": "tooShort", "keineMMDKennung": "noMMDSignature",
"zeigerAusserhalb": "pointerOutOfBounds",
"strukturUnvollständig": "truncatedStructure",
# --- MIDIWirkung -------------------------------------------------------
"controllerWert": "controllerValue", "controllerNummer": "controllerNumber",
"pitchbendAuf": "pitchBendUp", "pitchbendAb": "pitchBendDown",
"pitchbendSetzen": "setPitchBend", "modulationsrad": "modulationWheel",
"playseqSprung": "playSequenceJump", "holdSetzen": "setHold",
"ticksProZeile": "ticksPerRow", "polyphonerAftertouch": "polyphonicAftertouch",
"kanalAftertouch": "channelAftertouch", "tempoOderSonderfall": "tempoOrSpecial",
"sysexSenden": "sendSysEx", "lautstärkeController": "volumeController",
"blockWiederholen": "repeatRows", "sprungNächsteSequenz": "jumpToNextSequence",
"zeileWiederholen": "repeatRow", "verzögernOderRetrigger": "delayOrRetrigger",
"freierController": "assignableController", "ohneWirkungBeiMIDI": "noEffectOnMIDI",
"unbekannt": "unknown",
# --- TempoSonderfall ---------------------------------------------------
"retriggerZweimal": "retriggerTwice", "retriggerDreimal": "retriggerThreeTimes",
"verzögernHalbeZeile": "delayHalfRow", "verzögernEinDrittel": "delayOneThirdRow",
"verzögernZweiDrittel": "delayTwoThirdsRow", "wartenBisGesendet": "waitUntilSent",
"holdPedalAn": "holdPedalOn", "holdPedalAus": "holdPedalOff",
"songAnhalten": "stopSong", "noteStoppen": "stopNote", "tempoSetzen": "setTempo",
# --- Lautstärkelesart --------------------------------------------------
"siebenBit": "sevenBit", "hexadezimal": "hexadecimal", "dezimal": "decimal",
# --- Warnung.Art -------------------------------------------------------
"unbekannterBefehl": "unknownCommand",
"befehlOhneWirkungBeiMIDI": "commandWithoutMIDIEffect",
"kanalKollision": "channelCollision", "modlenStimmtNicht": "modlenMismatch",
"instrExtUngewöhnlich": "unusualInstrExtSize", "dumpUnvollständig": "incompleteDump",
"cmd3xFehlt": "missingCmd3xTable", "notenOhneMIDIKanal": "notesWithoutMIDIChannel",
"befehlMitAuffälligemWertebereich": "commandWithOddValueRange",
"sonstiges": "other",
# --- Notenbefund.Art ---------------------------------------------------
"noteOffOhneNote": "noteOffWithoutNote", "noteOffMittenImBlock": "noteOffMidBlock",
"amSongendeOffen": "openAtSongEnd",
# --- Eigenschaften und Funktionen --------------------------------------
"blöcke": "blocks", "Blöcke": "Blocks", "zellen": "cells", "zelle": "cell",
"spuren": "tracks", "spur": "track", "zeilen": "rows", "zeile": "row",
"nummer": "number", "größe": "size", "Größe": "Size", "länge": "length",
"Länge": "Length", "anzahl": "count", "daten": "data", "wert": "value",
"werte": "values", "seite": "page", "seiten": "pages", "seitenAnzahl": "pageCount",
"befehl": "command", "befehle": "commands", "note": "note",
"notenName": "noteName", "notenBytes": "noteBytes", "blockKopfBytes": "blockHeaderBytes",
"hatSections": "hasSections", "istLeer": "isEmpty", "istMIDI": "isMIDI",
"istSauber": "isClean", "istVollständig": "isComplete", "istAktuell": "isCurrent",
"istBeat": "isBeat", "klingt": "sounds",
"midiKanal": "midiChannel", "midiPreset": "midiPreset", "langesPreset": "longPreset",
"standardLautstärke": "defaultVolume", "transponierung": "transpose",
"noteOffUnterdrücken": "suppressNoteOff", "midiLautstärke": "midiVolume",
"hatSampleDaten": "hasSampleData", "midiAnfangsLautstärke": "initialMIDIVolume",
"rohdaten": "rawData", "nachrichten": "messages", "hersteller": "manufacturer",
"zusatzSeiten": "extraPages", "zusatzParameter": "extraParameters",
"siebenBitLautstärke": "sevenBitVolume", "lautstärkelesart": "volumeEncoding",
"lautstärkeHex": "volumeIsHex", "grundlautstärke": "defaultVolumeSetting",
"instrumente": "instruments", "dumps": "dumps", "sections": "sections",
"playsequenzen": "playSequences", "cmd3xController": "cmd3xControllers",
"diagnose": "diagnostics", "warnungen": "warnings", "hinweise": "notices",
"befehlsStatistik": "commandCounts", "befehlsFundstellen": "commandLocations",
"fundstellen": "locations", "ort": "location",
"standardTempo": "defaultTempo", "ticksProZeile": "ticksPerRow",
"bpmModus": "bpmMode", "zeilenProBeat": "rowsPerBeat",
"songTransponierung": "songTranspose", "mixingModus": "mixingMode",
"weitereSongs": "extraSongs", "dateigröße": "fileSize", "dateiname": "fileName",
"kennung": "signature", "passt": "fits", "zeiger": "pointer", "feld": "field",
"textFest": "fixedString",   # "text" bewusst NICHT: kollidiert mit SwiftUI TextField(text:)
"lade": "load", "datei": "file", "bytes": "bytes",
"leseBlock": "readBlock", "leseDumps": "readDumps", "leseCmd3x": "readCmd3x",
"anzahlSeiten": "extraPageCount", "werteAus": "analyse",
"erklärung": "explanation", "bedeutung": "meaning", "midiWirkung": "midiEffect",
"instrumentZeichen": "instrumentDigit", "prüfe": "check", "songFolge": "songOrder",
"folge": "order", "befunde": "findings", "sequenzPosition": "sequencePosition",
"aktivesInstrument": "activeInstrument", "letztesInstrument": "lastInstrument",
"offen": "sounding", "seit": "since", "vorige": "previous", "noten": "notes",
"instrument": "instrument", "kanal": "channel", "schlüssel": "key",
"nachArt": "byKind", "liste": "list", "beispiel": "example",
# --- zweite Runde: restliche deutsche Bezeichner -----------------------
"leer": "empty", "ergebnis": "result", "ende": "end", "grenze": "limit",
"ziffer": "digit", "ziffern": "digits", "namen": "names", "teile": "parts",
"erster": "first", "erstes": "first", "erwartet": "expected",
"tatsächlich": "actual", "treffer": "hits", "kollisionen": "collisions",
"benannte": "named", "belegt": "assigned", "stumm": "silent",
"klingend": "sounding", "proKanal": "byChannel", "zähler": "counter",
"schritt": "stride", "basis": "base", "roh": "raw", "typen": "types",
"nummern": "numbers", "tabelle": "table", "satt": "saturated",
"quote": "percentage", "gesamt": "total", "geladen": "loaded",
"auswahl": "selection", "fehler": "error", "aktiv": "current",
"aktiverBlock": "currentBlock", "alle": "all", "ordner": "folder",
"dateien": "files", "springeAnSongAnfang": "goToSongStart",
"weiterInSongreihenfolge": "stepInSongOrder", "zuBlock": "goToBlock",
"zeileVerschieben": "moveRow", "seitenSprung": "pageStep",
"sekundenProZeile": "secondsPerRow", "zeitImBlock": "timeInBlock",
"taktUndBeat": "barAndBeat", "öffnenDialog": "showOpenPanel",
"schließe": "close", "spurenEinfärben": "colourTracks",
"kopfzeile": "headerRow", "zeilenAnsicht": "rowView", "zelleAnsicht": "cellView",
"farbeDerSpur": "trackColour", "farbeDesInstruments": "instrumentColour",
"befehlsFarbe": "commandColour", "instrumentDerSpur": "trackInstrument",
"instrumentNameDerSpur": "trackInstrumentName", "gesamtBreite": "totalWidth",
"zeilenHöhe": "rowHeight", "zeilenNrBreite": "rowNumberWidth",
"spurBreite": "trackWidth", "hatFokus": "isFocused", "leerAnsicht": "emptyView",
"seitenleiste": "sidebar", "werkzeugleiste": "toolbar",
"positionsanzeige": "positionDisplay", "beschriftet": "labelled",
"patternSeite": "patternTab", "gruppe": "section", "kopf": "header",
"instrumentTabelle": "instrumentTable", "dumpTabelle": "dumpTable",
"befehlsTabelle": "commandTable", "springeZu": "goTo",
"blockEingabe": "blockInput", "nurPattern": "patternOnly", "bereich": "range",
"zeilenGesamt": "totalRows", "mitErweiterung": "withExtension",
"seitenGesamt": "totalPages", "proSeite": "perPage",
"velocityWerte": "velocityValues", "werteProBefehl": "valuesPerCommand",
"notenProInstrument": "notesPerInstrument", "ohneWirkung": "withoutEffect",
"cmd3xFehlt": "cmd3xMissing", "statistik": "counts", "stat": "stats",
"grund": "defaultVolumeValues", "insNr": "insNo",
"instrExtGröße": "instrExtSize", "iinfoGröße": "iinfoSize",
"nameLänge": "nameLength", "maxLänge": "maxLength",
"unterdrücken": "suppress", "anzahlBlöcke": "blockCount",
"benötigt": "needed", "anzahlInstrumente": "instrumentCount",
"instrExtNutzbar": "instrExtUsable", "nachrichten": "messages",
"vorhanden": "available", "zusatzSeiten": "extraPages",
# --- Testnamen ---------------------------------------------------------
"alleTestdateienLadenUndModlenStimmt": "allTestFilesLoadAndModlenMatches",
"keineUnbekanntenBefehleImTestmaterial": "noUnknownCommandsInTestFiles",
"keineKanalkollisionKlingenderInstrumente": "noChannelCollisionOfSoundingInstruments",
"befehlNullMitDatenIstNichtLeer": "commandZeroWithDataIsNotEmpty",
"befehlskatalogMIDISeite": "commandCatalogMIDISide",
"blockLayoutJeVersion": "blockLayoutPerVersion",
"notennamenWieInOctaMED": "noteNamesAsInOctaMED", "svolNachMIDI": "svolToMIDI",
"kurzeDateiWirdAbgewiesen": "shortFileIsRejected",
"falscheKennungWirdAbgewiesen": "wrongSignatureIsRejected",
"versionAusKennung": "versionFromSignature",
"velocityNachMessungAmOriginal": "velocityAsMeasuredOnOriginal",
"velocityIstVerdopplungMitNullbasis": "velocityIsDoublingFromZero",
"befehlserweiterungNurInMMD3Dateien": "commandExtensionOnlyInMMD3Files",
"befehl17LöstProSpurAufVerschiedeneKanäleAuf": "command17ResolvesPerTrackToDifferentChannels",
"dumpZerfälltInEinzelneSysExNachrichten": "dumpSplitsIntoIndividualSysExMessages",
"instrExtGrößeWirdRespektiert": "instrExtSizeIsRespected",
"patternAnsichtStimmtMitOctaMEDÜberein": "patternViewMatchesOctaMED",
"siebenBitLautstärkeWirdNichtSkaliert": "sevenBitVolumeIsNotScaled",
"tempoSonderfälle": "tempoSpecials",
"werteAb80SetzenDieGrundlautstärke": "valuesFrom80SetDefaultVolume",
}

def code_spans(text):
    """Zerlegt Swift-Quelltext in (start, ende, art) mit art aus
    {'code', 'comment', 'string'}.

    Beherrscht Zeilen- und verschachtelte Blockkommentare, einzeilige und
    mehrzeilige Zeichenketten sowie Interpolation `\\( ... )` — deren Inhalt ist
    wieder Code und darf selbst Zeichenketten enthalten.
    """
    spans=[]; i=0; n=len(text); start=0
    stapel=[]            # ('str', trenner) oder ('interp', klammertiefe)
    klammern=0

    def schnitt(bis, art):
        nonlocal start
        if bis>start: spans.append((start,bis,art))
        start=bis

    while i<n:
        in_zeichenkette = bool(stapel) and stapel[-1][0]=='str'
        if in_zeichenkette:
            trenner=stapel[-1][1]
            if text.startswith('\\(', i):
                schnitt(i+2,'string')          # das \( gehoert zur Zeichenkette
                stapel.append(('interp',klammern)); klammern+=1; i+=2; continue
            if text[i]=='\\': i+=2; continue
            if text.startswith(trenner,i):
                i+=len(trenner); stapel.pop(); schnitt(i,'string'); continue
            if trenner=='"' and text[i]=='\n':
                stapel.pop(); schnitt(i,'string'); continue
            i+=1; continue

        if text.startswith('//',i):
            schnitt(i,'code')
            j=text.find('\n',i); j=n if j<0 else j
            i=j; schnitt(i,'comment'); continue
        if text.startswith('/*',i):
            schnitt(i,'code')
            tiefe=1; j=i+2
            while j<n and tiefe:
                if text.startswith('/*',j): tiefe+=1; j+=2
                elif text.startswith('*/',j): tiefe-=1; j+=2
                else: j+=1
            i=j; schnitt(i,'comment'); continue
        if text.startswith('"""',i):
            schnitt(i,'code'); stapel.append(('str','"""')); i+=3; continue
        if text[i]=='"':
            schnitt(i,'code'); stapel.append(('str','"')); i+=1; continue
        if text[i]=='(': klammern+=1; i+=1; continue
        if text[i]==')':
            klammern-=1
            if stapel and stapel[-1][0]=='interp' and klammern==stapel[-1][1]:
                schnitt(i,'code')              # Inhalt der Interpolation war Code
                stapel.pop(); i+=1; continue   # die ) gehoert zur Zeichenkette
            i+=1; continue
        i+=1
    schnitt(n,'string' if (stapel and stapel[-1][0]=='str') else 'code')
    return spans


def prüfe_zerleger(text):
    """Die Zerlegung muss den Text exakt wiedergeben."""
    spans=code_spans(text)
    zusammen=''.join(text[a:b] for a,b,_ in spans)
    assert zusammen==text, "Zerleger verliert Text!"
    for (a,b,_),(c,d,_) in zip(spans, spans[1:]):
        assert b==c, f"Lücke zwischen {b} und {c}"
    return spans


PATTERN = re.compile(r'\b(' + '|'.join(sorted(map(re.escape, MAP), key=len, reverse=True)) + r')\b')
BACKTICK = re.compile(r'`([^`\n]+)`')

def ersetze_code(s):
    return PATTERN.sub(lambda m: MAP[m.group(1)], s)

def ersetze_kommentar(s):
    # nur Bezeichner in Rückwärtsstrichen mitziehen
    return BACKTICK.sub(lambda m: '`' + PATTERN.sub(lambda k: MAP[k.group(1)], m.group(1)) + '`', s)

def verarbeite(text):
    aus=[]
    for a,b,art in code_spans(text):
        teil=text[a:b]
        if art=='code':    aus.append(ersetze_code(teil))
        elif art=='comment': aus.append(ersetze_kommentar(teil))
        else:              aus.append(teil)
    return ''.join(aus)

if __name__ == '__main__':
    trocken = '--schreiben' not in sys.argv
    dateien = sorted(glob.glob('Sources/**/*.swift',recursive=True)+
                     glob.glob('Tests/**/*.swift',recursive=True))
    gesamt=0
    for f in dateien:
        alt=open(f,encoding='utf-8').read()
        assert alt==unicodedata.normalize('NFC',alt), f"{f} ist nicht NFC!"
        prüfe_zerleger(alt)
        neu=verarbeite(alt)
        if alt!=neu:
            n=sum(1 for a,b in zip(alt.split('\n'),neu.split('\n')) if a!=b)
            gesamt+=n
            print(f"  {f:<52} {n} Zeilen")
            # Sicherung: alle Zeichenketten muessen unveraendert bleiben
            sa=[alt[a:b] for a,b,art in code_spans(alt) if art=='string']
            sn=[neu[a:b] for a,b,art in code_spans(neu) if art=='string']
            assert sa==sn, f"{f}: Zeichenketten veraendert!"
            if not trocken: open(f,'w',encoding='utf-8').write(neu)
    print(f"\n{gesamt} geänderte Zeilen" + ("  (Probelauf, nichts geschrieben)" if trocken else "  geschrieben"))
