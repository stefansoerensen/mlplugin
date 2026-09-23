# Admin Guide: Claude Code Plugin `medialine-platform`

> **Zielgruppe:** `claude-config-dri` sowie Plattform- und IT-Administration.
> Für Installation und tägliche Nutzung siehe [developer-guide.md](./developer-guide.md).
>
> **Stand:** August 2026 · **Plugin-Version:** 1.7.x · **Repository:** <https://gitea.medialine.com/medialine/claude-plugin-platform>

---

## 1. Verantwortung und Aufbau

Das Repository ist zugleich **Marketplace** und **Plugin**:

```
.claude-plugin/marketplace.json   Katalog, listet medialine-platform
medialine-platform/               das Plugin — NUR dieses Verzeichnis wird ausgeliefert
docs/                             diese Dokumentation (nicht ausgeliefert)
README.md, QUARTERLY_REVIEW.md    Repo-Dokumentation (nicht ausgeliefert)
```

Eine einzelne Person hat die Rolle `claude-config-dri` in TaskTool und verantwortet:

- Review und Merge jedes PRs (`main` ist geschützt)
- Versionsvergabe und Release
- Triage der Vorschläge aus dem Feedback-Loop (`/admin/claude-feedback`)
- das Quartalsreview

**Wichtig für alle folgenden Abschnitte:** Ausgeliefert wird ausschließlich `medialine-platform/**`. Änderungen an `README.md`, `QUARTERLY_REVIEW.md` oder `docs/` erreichen keine Installation und brauchen keinen Versionssprung.

---

## 2. Entwickler-Onboarding

Jede Entwicklerin und jeder Entwickler braucht zwei Tokens von TaskTool. Für die Verbindung zu den MCP-Servern ist davon nur **einer** relevant: `MEDIALINE_MCP_TOKEN`. **Für Git gibt TaskTool keinen Token aus** — die Anmeldung an Gitea ist die eigene Entra-Anmeldung über den Git Credential Manager.

| Token | Wofür | Umgebungsvariable |
|---|---|---|
| MCP-Bearer | Claude Code → alle sechs MCP-Server | `MEDIALINE_MCP_TOKEN` |
| Jenkins-Token | mcp-jenkins, Jenkins-API | `MEDIALINE_JENKINS_TOKEN` |

**Ablauf:**

1. Die Person meldet sich einmal unter `https://gitea.medialine.com` mit Entra an; dadurch entsteht ihr Gitea-Konto.
2. Unter `/admin/users` die Rolle auf `developer` setzen. TaskTool nimmt das Gitea-Konto daraufhin in das Team `Developers` der Organisation `medialine` auf und meldet das Ergebnis. „no account" heißt: die Person hat sich noch nie an Gitea angemeldet (Schritt 1) — die Aufnahme passiert dann automatisch beim nächsten Aufruf ihrer Environment checks.
3. Die Person erzeugt ihre beiden Tokens selbst unter `/dev/me/setup` (**Generate my tokens**, Klartext nur einmal) und folgt den Schritten dort.
4. Prüfung über `/dev/me/setup` (Environment checks): Gitea-Konto gefunden, kürzlich angemeldet, Mitglied im Team `Developers`, beide Tokens aktiv.

Einmalig alle bestehenden Entwickler übernehmen: `POST /api/admin/gitea/sync-developers` (Standard: Probelauf, ändert nichts) prüfen, dann mit `?dry_run=false` ausführen.

> Konten, die noch einen alten, von TaskTool auf dem Gitea-Admin ausgestellten Token besitzen, sehen dort eine Warnung. Diese Tokens werden in einer späteren Phase widerrufen; bis dahin funktionieren sie.

TaskTool speichert ausschließlich den SHA-256-Hash. Ein Klartext lässt sich nicht wiederherstellen; bei Verlust muss neu ausgestellt werden.

### 2.1 Grenzen des Widerrufs

> **Achtung:** Ein Widerruf in TaskTool wirkt auf die MCP-Server und die API-Zugriffe. Er beendet **nicht** zwangsläufig den Git-Zugriff.
>
> Git authentifiziert je nach Arbeitsplatz über den Git Credential Manager (OAuth mit Refresh-Token) oder über einen direkt in der Repository-Konfiguration hinterlegten PAT. Beides ist von TaskTool unabhängig.
>
> Beim Offboarding daher zusätzlich:
> - die OAuth-Freigabe in Gitea entziehen,
> - vorhandene Gitea-PATs des Kontos widerrufen,
> - das Konto in Gitea deaktivieren.
>
> Ein in einer Remote-URL oder in `url.<...>.insteadOf` eingebetteter PAT bleibt sonst gültig.

---

## 3. Netzwerk und Erreichbarkeit

`gitea.medialine.com` und `tasktool.medialine.com` liegen im Overlay-Netz `100.64.0.0/10`. Ohne VPN scheitert bereits die Namensauflösung, nicht erst die Verbindung.

Ein privates CA-Zertifikat ist **nicht** im Einsatz. Beide Hosts nutzen ein öffentlich signiertes Zertifikat mit `*.medialine.com`. Anleitungen, die das Eintragen eines Firmen-CA-Zertifikats verlangen, sind veraltet.

Erste Diagnose bei Meldungen wie „Marketplace lässt sich nicht hinzufügen":

```bash
nslookup gitea.medialine.com     # keine Antwort  -> VPN nicht aktiv
nslookup tasktool.medialine.com  # eigener Host, eigene ACL
```

Beide Hosts liegen auf **unterschiedlichen** Overlay-Adressen. Ein Arbeitsplatz kann Gitea erreichen und TaskTool nicht — dann funktioniert der Marketplace, aber kein MCP-Server.

---

## 4. Release und Versionierung

### 4.1 Die Regel

**Jede Änderung unter `medialine-platform/` muss die Version in `medialine-platform/.claude-plugin/plugin.json` erhöhen — Dokumentationsänderungen eingeschlossen.**

Installationen werden anhand der Versionsnummer unterschieden. Bleibt die Version gleich, betrachtet der Installer das Plugin als aktuell und kopiert den neuen Inhalt **nie**. Die Änderung liegt dann im Marketplace-Klon, sieht gemergt aus und erreicht trotzdem keine einzige Session. Ein Entfernen und erneutes Hinzufügen des Marketplace behebt das **nicht**, weil auch dann die Version übereinstimmt.

| Sprung | Wann |
|---|---|
| Patch `1.0.x` | Korrektur, Präzisierung, umformulierte Rule — nichts hinzugefügt oder entfernt |
| Minor `1.x.0` | neuer Skill, neue Rule, neuer Agent, neuer Hook |
| Major `x.0.0` | entfernte oder umbenannte Konvention, potenziell brechender Hook |

Änderungen ausschließlich an `README.md`, `QUARTERLY_REVIEW.md` oder `docs/` brauchen **keinen** Sprung.

### 4.2 Ablauf

1. PR gegen `main`, Jenkins-Build abwarten.
2. Version erhöhen, falls `medialine-platform/**` betroffen ist.
3. Squash-Merge.
4. Merge-Commit taggen (`v1.x.y`).
5. Ankündigen, damit aktualisiert wird.

### 4.3 Propagation überprüfen

Die Versionsnummer allein ist **kein** Nachweis: Eine veraltete Installation meldet die aktuelle Nummer, wenn der Sprung vergessen wurde.

```bash
diff -rq ~/.claude/plugins/marketplaces/medialine/medialine-platform \
         ~/.claude/plugins/cache/medialine/medialine-platform/<version>
```

Außer `.in_use` darf nichts abweichen. Jede weitere Abweichung bedeutet: Das Release ist nicht angekommen.

### 4.4 Auf vergessene Sprünge prüfen

```bash
git log --oneline <letzter-tag>..main -- medialine-platform/
```

Jede Inhaltsänderung in diesem Bereich ohne Versionssprung hat **keine** Installation erreicht und muss nachträglich released werden.

---

## 5. Claude Desktop bereitstellen

Claude Desktop unterliegt anderen Regeln als Claude Code. Zwei Einschränkungen betreffen die Administration unmittelbar:

### 5.1 Marketplace

Über die Oberfläche akzeptiert Claude Desktop nur `github.com`, `gitlab.com` und `bitbucket.org`. Gitea ist auf diesem Weg **nicht** eintragbar.

Zwei Auswege:

- **Mirror.** Das Repository auf einen der drei Hosts spiegeln. Für einen privaten Mirror benötigt jede Person Lesezugriff über das eigene Konto.
- **Administrative Bereitstellung.** Über `allowedPluginMarketplaces` (Windows: `HKLM\SOFTWARE\Policies\Claude`) sind zusätzlich `"source": "git"` für selbst gehostete Server und `"source": "url"` möglich. `credentialKind: "userGit"` nutzt dabei den Credential Manager des angemeldeten Kontos.

### 5.2 MCP-Server

**Benutzerinnen und Benutzer können Remote-MCP-Server nicht selbst hinzufügen.** Sie stehen ausschließlich über `managedMcpServers` oder Organisations-Plugins bereit. Das Spiegeln des Marketplace ändert daran nichts — die Einschränkung betrifft die Server, nicht die Quelle.

Für persönliche Tokens ist ein `headersHelper` der geeignete Weg: ein lokal ausgeführtes Programm, das den Header zur Laufzeit erzeugt, sodass keine gemeinsame Zeichenkette in der Konfiguration steht.

```json
[
  {
    "name": "medialine-gitea",
    "url": "https://tasktool.medialine.com/mcp/gitea/mcp",
    "headersHelper": "C:\\Program Files\\Medialine\\mcp-auth.exe",
    "headersHelperTtlSec": 900
  }
]
```

> `headersHelper` wird **nur** aus `managedMcpServers` gelesen, nicht aus der `.mcp.json` eines Plugins.

### 5.3 Fehlermeldung richtig deuten

Meldet ein Arbeitsplatz „Registrierung beim Anmeldedienst … fehlgeschlagen" und schlägt eine OAuth-Client-ID vor, ist das **irreführend**. Die Server verwenden kein OAuth. Der Ablauf dahinter: fehlender Token → HTTP 401 → Claude Desktop versucht eine OAuth-Registrierung → es existieren keine Discovery-Endpunkte → Abbruch.

Reihenfolge der Prüfung:

1. Ist `MEDIALINE_MCP_TOKEN` im Kontext des gestarteten Prozesses gesetzt? Claude Desktop erbt die Umgebung von `explorer.exe`; eine in einem Terminal gesetzte Variable erreicht die Anwendung **nicht**. Verlässlich wird sie erst nach Ab- und Anmeldung übernommen.
2. Ist der Token gültig? Ein widerrufener Token erzeugt dieselbe Meldung.
3. Ist der Arbeitsplatz über eine administrative Bereitstellung versorgt? Ohne sie stehen die Server nicht zur Verfügung.

---

## 6. Feedback-Loop

Claude meldet über `mcp-plugin.propose_update` Lücken zurück; daraus entsteht ein Entwurfs-PR.

Triage unter `/admin/claude-feedback` oder über `mcp-plugin.list_recent_proposals`.

Bei der Bewertung zwei Punkte beachten:

- **Ein Proposal-PR enthält zunächst nur einen Platzhalter.** Der eigentliche Inhalt steht in der Beschreibung. Ein Merge ohne Ausarbeitung fügt lediglich eine Stub-Datei hinzu und ändert nichts.
- **Die Zieldatei prüfen.** Vorschläge benennen häufig eine Rule oder einen Skill, obwohl die Ursache in einem anderen Repository liegt — etwa im Scaffold-Generator. Eine Konvention verhindert dann künftige Fälle, behebt aber keinen einzigen bestehenden.

---

## 7. Quartalsreview

Vollständige Checkliste in `QUARTERLY_REVIEW.md`. Kern:

- **Skills:** Entsprechen sie noch der Realität? Container, Endpunkte, Pfade.
- **Rules:** Braucht das aktuelle Modell die Regel noch? Regeln veralten mit besseren Modellen.
- **Agents:** Passen Rolle und Werkzeugliste?
- **Hooks:** Trägt jeder Hook noch etwas bei?
- **Version:** Auf vergessene Sprünge prüfen (4.4) und Propagation verifizieren (4.3).

> Ein defekter Hook, ein veraltetes Plugin und eine nicht angekommene Änderung sind aus einer laufenden Session heraus **nicht** erkennbar. Alles drei sieht von innen unauffällig aus. Deshalb gehören diese Prüfungen in das Review und nicht in den Alltag.

---

## 8. Weiterführend

- Nutzung und Installation: [developer-guide.md](./developer-guide.md)
- Repository: <https://gitea.medialine.com/medialine/claude-plugin-platform>
- Quartalsreview: `QUARTERLY_REVIEW.md`
- Claude Desktop Bereitstellung: <https://claude.com/docs/third-party/claude-desktop/extensions>
