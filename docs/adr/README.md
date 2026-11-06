# Architektur-Entscheidungen

Jede größere technische Entscheidung bekommt eine Datei `NNNN-kurzer-titel.md`, fortlaufend nummeriert. ADR 0001 (PSP-Grafik) und ADR 0002 (PS2-JIT) sind durch den Plan vergeben.

| ADR | Titel | Status |
| --- | --- | --- |
| [0001](0001-psp-grafik.md) | PSP-Grafik: Vulkan über MoltenVK | Vorgeschlagen |
| [0002](0002-ps2-jit.md) | PS2 mit JIT | Vorgeschlagen, Gerätetest ausstehend |
| [0003](0003-kerne-als-eingebettete-frameworks.md) | Kerne als eingebettete, nicht gelinkte Frameworks | Vorgeschlagen, Annahme mit der M0-Abnahme |
| [0004](0004-xcode-projekt-per-xcodegen.md) | Xcode-Projekt per XcodeGen | Vorgeschlagen, Annahme mit der M0-Abnahme |

Aufbau jeder Datei:

```markdown
# NNNN · Titel

Status: Vorgeschlagen | Angenommen | Abgelöst durch NNNN · Datum

## Kontext
## Optionen
## Entscheidung
## Folgen
```
