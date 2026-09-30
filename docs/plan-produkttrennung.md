# Migrationsplanung: Plugin-Trennung für TaskTool als Produkt

> **Stand:** 29.09.2026 · **Plugin-Version:** 1.8.0
> **Backlog-Bezug:** `s41` (Plugin aufteilen) · `s39` (Auslieferungsmodell) · `s40` (Grenzregel) · `s38` (Forge-Settings) · `s37` (Core-Sperre) · `s01`/`s02` (Plattformagnostik)
>
> Ersetzt die erste Fassung vom 24.09. Die damalige Analyse gilt weiter; neu ist die
> Einordnung in den Backlog und in den GitLab-Cutover.

---

## 1. Was es an Plänen schon gibt

| Quelle | Inhalt | Bezug zum Plugin |
|---|---|---|
| Backlog `s41` | „Plugin aufteilen: generischer Produktteil vs. Overlay" | **Der Auftrag selbst.** Status `inbox`, Vorschlag `backlog` |
| Backlog `s39` | Auslieferungsmodell (Repo / Stack / SaaS / OEM) | Blockiert `s41`. Hängt seinerseits an `s20` (K8s) |
| Backlog `s40` | Grenzregel: alles zwischen Produkt und Kundenrepo über Artefakte | Blockiert `s41`. **Einzige Entscheidung, die ohne `s20` fallen kann** |
| Backlog `s38` | Org-/Repo-Referenzen zentralisieren, Forge-Settings im Admin | Deckungsgleich mit der Parametrisierung des Plugins |
| Backlog `s37` + 12 Schritte | Core-Repos für Developer sperren | Trifft das Plugin unmittelbar, siehe Abschnitt 4 |
| Artefakt „Gitea to GitLab" | Host-Wechsel, 7 Phasen | Phase 5 hat das Plugin als **Gate** |
| `core-plugin-platform` | `claude-plugin-platform` bleibt in `medialine` | **Entschieden.** Kein Repo-Umzug nötig |

## 2. Die Abhängigkeitskette

```
s20 (K8s-Grundsatz)  ──►  s39 (Auslieferungsmodell)  ──┐
                                                        ├──►  s41 (Plugin-Schnitt)
s40 (Grenzregel Artefakte)  ─────────────────────────── ┘
```

**Der Schnitt ist doppelt blockiert.** Das deckt sich mit der Einschätzung in `s41`
selbst („Der Schnitt lässt sich erst ziehen, wenn das Auslieferungsmodell steht")
und mit dem Vorschlag, den Eintrag auf `backlog` zu setzen.

Daraus folgt aber **nicht**, dass bis dahin nichts zu tun ist. Es gibt Vorarbeit,
die von keiner dieser Entscheidungen abhängt und den späteren Schnitt billig macht.
Abschnitt 5 listet sie.

## 3. Befund: zwei Umbenennungen auf Kollisionskurs

Zwei laufende Vorhaben benennen dieselben Dinge um:

| Vorhaben | Umbenennung |
|---|---|
| GitLab-Cutover, Phase 5 | `medialine-gitea` → `medialine-gitlab` (MCP-Server, nginx-Slug, Plugin-Registrierung) |
| Produktschnitt `s41` | `medialine-*` → produktneutrale Namen |

Beide ändern **Werkzeugnamen**. Jede Berechtigungsliste in `.claude/settings.json`
zeigt danach ins Leere — in allen angebundenen Repos, für alle Entwickler, gleichzeitig.

**Empfehlung: in einem Ereignis bündeln.** Zweimal denselben Bruch auszulösen kostet
doppelt und verdoppelt das Risiko, dass Sessions danach stillschweigend Falsches tun.
Wenn der GitLab-Cutover zuerst kommt, sollte er die Server gleich produktneutral
benennen, statt `gitea` durch `gitlab` zu ersetzen.

## 4. Befund: die Core-Sperre bricht Plugin-Verweise

Nach `s37` sehen Developer die Core-Repos nicht mehr. Das Plugin verweist heute an
**vier Stellen** dorthin:

| Datei | Verweis |
|---|---|
| `skills/platform-services/SKILL.md` | `infrastructure`, `cicd-service`, `auth-service`, `tasktool` |
| `skills/object-storage/SKILL.md` | `infrastructure` (MinIO-Doku) |
| `skills/auth-integration/SKILL.md` | `auth-service` |
| `agents/integrator.md` | `infrastructure` |

`infrastructure` allein kommt fünfmal vor. Für Developer laufen diese Links nach der
Sperre auf `404` — genau die Fehlermeldung, die im Onboarding „der Admin hat dich
noch nicht hinzugefügt" bedeutet. Das wird zu Fehlmeldungen führen.

Der Backlog kennt den verwandten Fall bereits (`core-shared-api-doc`: die shared-API
muss ins Plugin, weil Developer den Code danach nicht mehr lesen können). Die vier
Verweise oben stehen dort noch nicht.

**Aufgabe:** Vor oder mit dem Transfer entweder die Verweise entfernen, oder als
„nur für Plattform-Entwickler" kennzeichnen, damit klar ist, dass ein 404 dort
erwartet ist.

## 5. Vorarbeit, die nicht blockiert ist

Drei Pakete. Alle drei sind rückwärtskompatibel, einzeln lieferbar und machen den
späteren Schnitt zu einem Verschieben von Dateien.

### V1 — Parametrisierung (deckt sich mit `s38`)

Fest verdrahtete Werte aus dem Plugin entfernen:

- MCP-URLs auf `https://${TASKTOOL_HOST}/mcp/...`. Plugin-Manifeste unterstützen
  Umgebungsvariablen in `url` und `headers`.
- Hostnamen in den Skills durch Platzhalter, mit dem Medialine-Wert als Beispiel.
- `port-allocation` auf die Registry umstellen statt auf die statische Tabelle —
  TaskTool bietet `list_ports` und `get_next_available_port` bereits an.
- Org-Referenzen (`medialine/...`) durch die Variablen aus `s38` ersetzen:
  `app_org`, `core_org`, `plugin_repo`.

`s38` ist für „nach dem Transfer" vorgesehen, damit sich nicht Repos und Referenzen
gleichzeitig bewegen. Der Plugin-Anteil kann davon abweichen: Das Plugin zieht nicht
um, es referenziert nur.

### V2 — Folgen der Core-Sperre

- Die vier Verweise aus Abschnitt 4 bereinigen.
- `core-shared-api-doc` umsetzen: shared-API (auth_middleware, logging_config,
  health) im Skill `auth-integration` beschreiben.

Terminlich gebunden an `s37` Schritt 3, nicht an den Produktschnitt.

### V3 — Inventar Produkt gegen Overlay

Jede Datei einmal klassifizieren: Produkt, Overlay oder gemeinsam. Ergebnis ist eine
Liste, kein Code. Zwei Punkte sind dabei inhaltlich offen und brauchen eine
Entscheidung, keine Analyse:

- **VIBES aufteilen.** Ein Teil ist Produkt, ein Teil Hausstil. Die Grenze zu ziehen
  ist eine Festlegung.
- **`cloud-only` und `jenkins-pipeline`.** Beide beschreiben ein Deployment-Modell,
  das mit `s20` noch offen ist. Vorher nicht generisch umschreiben — sonst zweimal.

## 6. Der Schnitt selbst, sobald `s39` und `s40` stehen

| Plugin | Inhalt | Zielgruppe |
|---|---|---|
| **Produktteil** | Auth, Pulse, Assistant, Object Storage, Vector-Search, Ports, App-Baseline, Doku-Regel, Stack, Produkt-Teil von VIBES, PM-Skills, Feedback-Loop | Entwickler beim Kunden |
| **Overlay** | Medialine-Hostnamen, belegte Ports, Entra-Anbindung, Hausregeln, Beispiele aus Winline und Boomi | Nur Medialine |

Der Overlay-Teil ist nach V1 voraussichtlich sehr klein. Ob daraus ein eigenes Plugin
wird oder eine `CLAUDE.md`-Ebene je Repo, entscheidet sich erst, wenn sichtbar ist,
wie viel übrig bleibt.

**Kernaussage aus der ersten Analyse, die weiter gilt:** Das ist keine
Inhaltstrennung, sondern eine Parametrisierung. Nachdem Stack, Port-Register und ein
Teil von VIBES dem Produkt zugeordnet sind, bleibt an Medialine-Spezifischem fast
kein Inhalt übrig — nur Konfigurationswerte.

## 7. Reihenfolge

1. **V2** — an `s37` gekoppelt, sonst brechen Verweise beim Transfer.
2. **V1** — jederzeit, unabhängig von allem anderen.
3. **V3** — jederzeit; das Ergebnis ist die Vorlage für den Schnitt.
4. **`s40` entscheiden** — die einzige Entscheidung ohne `s20`-Abhängigkeit, und sie
   entschärft `s37` mit.
5. **`s20` → `s39`** — außerhalb dieses Plans.
6. **Schnitt (`s41`)** — Dateien verschieben.
7. **Umbenennung** — gebündelt mit dem GitLab-Cutover, einmalig, angekündigt.

## 8. Offene Entscheidungen

| Thema | Backlog | Blockiert |
|---|---|---|
| K8s-Grundsatz | `s20` | `s39`, damit mittelbar `s41` |
| Auslieferungsmodell | `s39` | `s41` |
| Grenzregel Artefakte | `s40` | `s41`, `s01`, `s03`, `s37` |
| Produktname | — | Plugin-Namen, MCP-Namen, Verzeichnisse |
| VIBES: Produkt gegen Hausstil | — | Zuschnitt in Abschnitt 6 |
| Reihenfolge GitLab-Cutover gegen Produktschnitt | — | Abschnitt 3 |

## 9. Was hier bewusst nicht drinsteht

- **Weitere Coding-Agent-Stacks** (`s02`, OpenCode/OpenChamber). Eine Vorprüfung
  ergab: Skills und Rules sind weitgehend portabel, Hooks müssten neu gebaut werden,
  einen Marketplace gibt es dort nicht. Das gehört hinter den Schnitt, wie `s02`
  selbst vermerkt.
- **Eigene Feedback-Umsetzung für TaskTool.** Pulse sammelt Feedback zu den Apps,
  nicht zum Produkt. Eigenes Vorhaben.
