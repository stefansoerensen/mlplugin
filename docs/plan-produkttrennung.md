# Plan: Trennung des Plugins für TaskTool als Produkt

> **Status:** Zurückgestellt. **Blockiert durch:** die Entscheidung über den Produktnamen.
> Nichts aus diesem Plan wird umgesetzt, bevor der Name feststeht — er bestimmt die
> Plugin-Namen, die MCP-Server-Namen und die Verzeichnisstruktur.
>
> **Stand:** September 2026 · **Ausgangsversion:** `medialine-platform` 1.7.5

---

## 1. Warum

TaskTool wird ein Produkt, das an Kunden ausgeliefert wird. Die Repositories werden
getrennt: TaskTool-Core auf der einen Seite, die Medialine-eigenen Apps auf der
anderen. Das Plugin muss diese Trennung nachvollziehen.

Ziel sind zwei voneinander unabhängige Plugins:

- eines für **Entwickler beim Kunden**, die Apps auf TaskTool bauen,
- eines für **Plattform-Entwickler**, die TaskTool selbst bauen.

Der Mehrwert des Produkts ist die durchgängige Plattform — von der Idee über das
Vibecoding und den Betrieb bis zum End of Life einer App. Das Plugin ist damit
**Teil des Produkts**, nicht Beiwerk: Es ist der Vibecoding-Anteil dieser Kette.

---

## 2. Gesicherte Annahmen

Bestätigt am 24.09.2026:

1. TaskTool wird beim Kunden betrieben, als eigene Instanz. Medialine betreibt
   selbst eine Instanz des Produkts.
2. Zum ausgelieferten Umfang gehören auch Pulse, Assistant-Service,
   ext-api-service, cicd-service, vector-service, MinIO und die sechs MCP-Server —
   nicht nur das Portal.
3. Kunden bauen mit eigenen Entwicklern eigene Apps auf TaskTool.
4. Jenkins beziehungsweise cicd-service ist Teil des Produkts.
5. Der vorgeschriebene Stack (FastAPI, React, Postgres) ist **zunächst Teil des
   Produkts**. Er soll später konfigurierbar werden.
6. Das Port-Register gehört zum Produkt, weil TaskTool die Plattform für den
   Betrieb der Apps ist.
7. VIBES ist **teilweise** Produkt und teilweise Medialine-Hausstil. Die Grenze
   ist noch nicht gezogen.
8. Der Plugin-Feedback-Loop (`propose_update`) gehört **ins Produkt**. Sowohl das
   interne Produkt-Plugin als auch das Kunden-Plugin werden laufend verbessert,
   und beide brauchen den Rückkanal.

### Zuordnung der Repositories

- **Core:** `tasktool`, `auth-service`, `ext-api-service`, `cicd-service`,
  `assistant-service`, `pulse`, `docai-service`, `infrastructure`, `mcp-servers`,
  `shared`
- **Apps:** `leads-united`, `klar`, `aboabrechnung`, `mietkalkulator`,
  `quote-parser`, `dkv-analyser`, `cccalculator`, `winline-dict-mcp` und weitere

---

## 3. Die zentrale Erkenntnis

**Das ist keine Inhaltstrennung, sondern eine Parametrisierung.**

Die ursprüngliche Vermutung war, Inhalte in zwei Töpfe zu sortieren: generisch
gegen Medialine-spezifisch. Nachdem Stack, Port-Register und ein Teil von VIBES
dem Produkt zugeordnet sind, bleibt bei „Medialine-spezifisch" **fast kein Inhalt**
übrig.

Was übrig bleibt, sind Konfigurationswerte:

- Hostnamen (`tasktool.medialine.com`, `gitea.medialine.com`)
- die konkret belegten Ports
- die Anbindung an Entra ID
- Beispiele aus Winline, Boomi und MLAG

Der Inhalt bleibt also weitgehend, wo er ist. Er muss nur aufhören, Medialine fest
zu verdrahten. Erst danach ist der Schnitt im Wesentlichen ein Verschieben von
Dateien.

### Beispiel Port-Register

Der Skill `port-allocation` enthält heute eine statische Tabelle belegter Ports.
TaskTool hat dafür aber bereits einen Registry-MCP-Server mit `list_ports` und
`get_next_available_port`. Die Tabelle ist also nicht das Produkt, sondern eine
veraltete Kopie dessen, was die Instanz ohnehin weiß.

Für einen Kunden muss der Skill die Registry **abfragen**, statt eine Liste zu
zeigen. Dasselbe Muster ist an weiteren Stellen zu erwarten.

---

## 4. Phasen

### Phase 0 — Klären, was nicht am Plugin hängt

Zwei Punkte blockieren spätere Phasen und sind keine Plugin-Arbeit:

- **Deployment-Modell.** Offen, ob der Kunde einen kompletten Stack auf einen
  Docker-Host deployed, ob Docker mitgeliefert wird, oder ob es Kubernetes wird.
  Davon hängt ab, was in `cloud-only` und `jenkins-pipeline` stehen kann. Solange
  das offen ist, werden diese beiden Skills **nicht** generisch umgeschrieben —
  sonst zweimal.
- **VIBES aufteilen.** Jemand muss die 179 Zeilen durchgehen und markieren, was
  Produkt ist und was Hausstil. Inhaltliche Entscheidung, Ergebnis ist eine Liste.

### Phase 1 — Parametrisieren, ohne zu trennen

Das Plugin bleibt eins. Nur die fest verdrahteten Werte verschwinden.

- MCP-URLs auf `https://${TASKTOOL_HOST}/mcp/...` umstellen. Plugin-Manifeste
  unterstützen Umgebungsvariablen in `url` und `headers`.
- Hostnamen in den Skills durch Platzhalter ersetzen, mit dem Medialine-Wert als
  Beispiel.
- `port-allocation` auf die Registry umstellen statt auf die statische Tabelle.
- Medialine-Beispiele als solche kennzeichnen oder ersetzen.

**Warum zuerst:** Das ist die eigentliche Arbeit, sie ist rückwärtskompatibel, und
sie nützt sofort. Risiko gering, jede Änderung einzeln prüfbar.

### Phase 2 — Schnitt in zwei Plugins

Erst danach, weil ab hier Korrekturen teurer werden.

| Plugin | Inhalt | Zielgruppe |
|---|---|---|
| **Kunden-Plugin** | Auth, Pulse, Assistant, Object Storage, Vector-Search, Ports, App-Baseline, Doku-Regel, Stack, Produkt-Teil von VIBES, PM-Skills, Feedback-Loop | Entwickler beim Kunden |
| **Produkt-Plugin** | MCP-Server entwickeln, Diag, Registry-Interna, CI/CD-Pipeline, Architektur der Dienste, Feedback-Loop | Wer TaskTool selbst baut |

**Medialine-spezifisch** wird voraussichtlich kein drittes Plugin, sondern
Konfiguration plus wenige Hausregeln. Ob das eine `CLAUDE.md`-Ebene pro Repository
wird oder ein dünnes Overlay-Plugin, wird entschieden, wenn nach Phase 1 sichtbar
ist, wie viel übrig bleibt. Erwartung: sehr wenig.

**Gemeinsame Hygiene-Regeln** (`conventional-commits`, `security`,
`branch-workflow`, `documentation`) gehen in beide Plugins. Das ist bewusste
Doppelpflege: Die Vorgabe lautet „völlig unabhängig", und ein drittes Basis-Plugin
würde die Abhängigkeit wieder aufmachen. Das Driftrisiko ist bekannt und
akzeptiert.

### Phase 3 — Umbenennung der MCP-Server

Heute heißen sie `medialine-diag`, `medialine-gitea` und so weiter. Im Produkt
müssen sie neutral heißen.

Das ist der einzige echte Bruch im ganzen Vorhaben: Die Werkzeugnamen ändern sich,
und jede Berechtigungsliste in `.claude/settings.json` zeigt ins Leere. Betroffen
sind alle Repositories mit Plugin-Anbindung sowie jede Entwicklerkonfiguration.

Bewusst ans Ende gestellt. Einmal durchführen, vorher ankündigen, an einem Termin.

### Phase 4 — Auslieferung

Noch offen. Die Entscheidung hängt an Phase 0: Wird TaskTool als kompletter Stack
ausgeliefert, liegt nahe, dass die Instanz ihren Marketplace selbst bereitstellt
(`https://tasktool.<kunde>/plugins/marketplace.json`). Vorteile: Die
Plugin-Version passt immer zur installierten Version, der Kunde braucht keinen
Zugang zu fremden Git-Servern, und die Host-Beschränkung von Claude Desktop
(nur github, gitlab, bitbucket) entfällt, weil `source: url` zulässig ist.

---

## 5. Offene Entscheidungen

| Thema | Status | Blockiert |
|---|---|---|
| **Produktname** | offen | alles — Plugin-Namen, MCP-Namen, Verzeichnisse |
| Deployment-Modell (Docker / Kubernetes) | offen | `cloud-only`, `jenkins-pipeline` |
| VIBES: Produkt gegen Hausstil | offen | Zuschnitt Phase 2 |
| Auslieferungsweg | offen | Phase 4 |
| Form des Medialine-Rests | offen | entscheidet sich nach Phase 1 |

Eigenes Vorhaben, hier nur vermerkt: Für TaskTool als Produkt ist eine **eigene
Feedback-Umsetzung** zu planen. Pulse sammelt Feedback zu den Apps; Feedback zum
Produkt selbst ist damit nicht abgedeckt.

---

## 6. Nächster Schritt

Sobald der Produktname feststeht: Phase 1 beginnen, angefangen bei den MCP-URLs.
Das ist die kleinste abgeschlossene Einheit und läuft unabhängig von den übrigen
offenen Punkten.
