# CLibretro

C-Target von LibretroKit:

- `include/libretro.h`: die Libretro-API, unverändert übernommen (Herkunft unten).
- `include/arcfold_log.h` und `arcfold_log.c`: der Log-Shim für `RETRO_ENVIRONMENT_GET_LOG_INTERFACE` (ADR 0005). `retro_log_printf_t` ist variadisch, Swift kann ihn weder umsetzen noch aufrufen. Der Shim zählt Zeilen unter der Mindeststufe (Standard `RETRO_LOG_WARN`) nur, formatiert alle übrigen mit `vsnprintf` in einen Puffer auf dem Stack und reicht sie an eine nicht-variadische Senke aus Swift weiter.
- `include/arcfold_signpost.h` und `arcfold_signpost.c`: Intervall „retro_run“ und Ereignis „resync“ des Emulations-Threads über die `os_signpost`-Makros. `OSSignposter` legt pro Intervall Speicher an, die Makros nicht.
- `include/CLibretro.h`: Umbrella-Header, aus dem SwiftPM die Module-Map baut. Ein neuer Header muss hier eingetragen werden.

## libretro.h

| | |
| --- | --- |
| Quelle | https://github.com/libretro/libretro-common/blob/d9597c359a5ca8399a4e244f816e7e975a92a2aa/include/libretro.h |
| Commit | `d9597c359a5ca8399a4e244f816e7e975a92a2aa` (28. Oktober 2026, letzter Commit, der die Datei geändert hat) |
| Abgerufen | 6. November 2026 per `gh api` |
| SHA-256 | `5b6d8fe1056a39591ee6c479512eed4a6f6efd8f89f64f10cf8b4757a2aa48a0` |
| Lizenz | MIT, siehe Kopf der Datei. Gilt nur für diesen Header und ist mit GPL-3.0 vereinbar |

Die Datei wird nicht von Hand geändert. Aktualisieren:

```bash
sha=$(gh api 'repos/libretro/libretro-common/commits?path=include/libretro.h&per_page=1' --jq '.[0].sha')
gh api "repos/libretro/libretro-common/contents/include/libretro.h?ref=$sha" \
  -H 'Accept: application/vnd.github.raw' > include/libretro.h
```

Danach Commit, Datum und Prüfsumme oben eintragen.
