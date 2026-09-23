# Developer Guide: Claude Code Plugin `medialine-platform`

> **Zielgruppe:** Entwicklerinnen und Entwickler, die mit Claude Code an Medialine-Projekten arbeiten.
> Für Betrieb, Bereitstellung und Release siehe [admin-guide.md](./admin-guide.md).
>
> **Stand:** August 2026 · **Plugin-Version:** 1.7.x · **Repository:** <https://gitea.medialine.com/medialine/claude-plugin-platform>

---

## 1. Worum geht es?

Das Plugin `medialine-platform` liefert allen Entwicklerinnen und Entwicklern **eine gemeinsame Arbeitsgrundlage für Claude Code**. Statt in jedem Repository dieselben Konventionen erneut zu erklären, werden sie an einer Stelle gepflegt und automatisch in jede Session geladen.

| Bestandteil | Wirkung |
|---|---|
| **Rules** | Werden in **jeder** Session geladen. Verbindliche Konventionen (Tech-Stack, Branch-Workflow, Security, Dokumentationspflicht). |
| **Skills** | Werden **bei Bedarf** geladen, sobald das Thema auftaucht. Anleitungen für Plattformdienste (SSO, Pulse, Assistant, MinIO, Vector-Search …). |
| **Agents** | Spezialisierte Subagenten (Backend, Frontend, Integration, Review). |
| **Hooks** | Automatische Prüfungen vor bestimmten Aktionen, etwa die Erinnerung an die Doku vor einem Commit. |
| **MCP-Server** | Sechs Server-Registrierungen für den direkten Zugriff auf Gitea, Jenkins, Diagnose und Registry. |

Der zentrale Nutzen: **Wissen über die Plattform steht dort zur Verfügung, wo gearbeitet wird.** Ein Dienst wie Pulse oder der KI-Assistent wird nur dann genutzt, wenn Claude in der jeweiligen Session überhaupt weiß, dass es ihn gibt.

---

## 2. Voraussetzungen

### 2.1 Netzwerkzugang

`gitea.medialine.com` und `tasktool.medialine.com` liegen im internen Overlay-Netz (`100.64.0.0/10`). Ohne aktive VPN-Verbindung schlägt bereits die Namensauflösung fehl.

```bash
nslookup gitea.medialine.com
```

Kommt keine Antwort oder `NXDOMAIN`, ist die VPN-Verbindung nicht aktiv. Alles Weitere erübrigt sich, bis das behoben ist.

> Ein separates CA-Zertifikat ist **nicht** erforderlich. Beide Hosts nutzen ein öffentlich signiertes Zertifikat.

### 2.2 Plattform-Token

Für die MCP-Server wird ein persönlicher Token benötigt. Alle sechs Server verwenden **denselben** Token: `MEDIALINE_MCP_TOKEN`. Für `mcp-jenkins` und direkte Jenkins-Aufrufe kommt `MEDIALINE_JENKINS_TOKEN` hinzu. **Für Git wird kein Token benötigt** (siehe 2.3).

1. Rolle `developer` in TaskTool anfordern. Ein Admin setzt sie unter `/admin/users` (siehe [admin-guide.md](./admin-guide.md#2-entwickler-onboarding)).
2. Unter `/dev/me/setup` auf **Generate my tokens** klicken. Der Klartext wird **nur einmal** angezeigt — als fertiges Skript.
3. Das Skript in PowerShell einfügen. Es setzt beide Variablen dauerhaft:

```powershell
[Environment]::SetEnvironmentVariable("MEDIALINE_MCP_TOKEN",     "mlmcp_...",     "User")
[Environment]::SetEnvironmentVariable("MEDIALINE_JENKINS_TOKEN", "mljenkins_...", "User")
```

4. **VS Code vollständig beenden und neu starten.** Ein Reload des Fensters genügt nicht, da Umgebungsvariablen nur von neu gestarteten Prozessen übernommen werden.

### 2.3 Git-Anmeldung für Gitea

Gitea verlangt für jeden Zugriff eine Anmeldung, auch für das Klonen des Plugins. Die Anmeldung ist die **eigene Medialine-Anmeldung (Entra ID)** — es gibt kein Gitea-Passwort und keinen Token, den man eintragen müsste.

**So läuft es:**

1. `https://gitea.medialine.com` öffnen und **Sign in with Medialine Entra ID** wählen. Beim ersten Mal entsteht dadurch das Gitea-Konto.
2. Einem Admin Bescheid geben. Sobald der Admin die Rolle `developer` in TaskTool vergibt, nimmt TaskTool das Gitea-Konto in das Team `Developers` der Organisation `medialine` auf (Voraussetzung: Schritt 1 ist erledigt). Vorher liefern Repositories `404 not found`.
3. Einmal in einem normalen Terminal:

```powershell
git ls-remote https://gitea.medialine.com/medialine/claude-plugin-platform.git
```

Git für Windows bringt den **Git Credential Manager** mit. Er erkennt Gitea, **öffnet den Browser**, die Anmeldung läuft über Entra, und der Manager speichert das Ergebnis im Windows Credential Manager (Einträge `git:https://oauth2@gitea.medialine.com` und `git:https://refresh_token.gitea.medialine.com`). Ab dann funktionieren Klonen, Pull und Push aus jedem Programm ohne Rückfrage — auch aus Claude Code, das selbst keinen Browser öffnen kann.

Erscheint eine Liste mit Zeilen, die auf `refs/heads/main` enden, ist alles bereit.

> **Wichtig:** Git liest **keine** Umgebungsvariablen. `MEDIALINE_MCP_TOKEN` und `MEDIALINE_JENKINS_TOKEN` sind für die MCP-Server und Jenkins da, nicht für Git.

**Fragt Git nach Benutzername und Passwort statt den Browser zu öffnen — oder „klappt" es, ohne dass je ein Browser aufging?** Dann verwendet Git eine alte gespeicherte Anmeldung oder einen alten Token weiter. Beides entfernen (eine Meldung „nicht gefunden" ist in Ordnung):

```powershell
cmdkey /delete:LegacyGeneric:target=git:https://gitea.medialine.com
git config --global --unset http.https://gitea.medialine.com/.extraheader
```

Danach den `git ls-remote`-Befehl erneut ausführen; jetzt öffnet sich der Browser. Ein Medialine-Passwort funktioniert an dieser Stelle **nie** — Gitea kennt es nicht. (macOS: statt der ersten Zeile den Eintrag „gitea.medialine.com" in der Schlüsselbundverwaltung löschen.)

**macOS:** `brew install git git-credential-manager`. **Linux:** `git-credential-oauth` (Paket der Distribution oder <https://github.com/hickford/git-credential-oauth>); es ist in Gitea vorregistriert und arbeitet genauso über den Browser.

**Prüfen**, ob die Anmeldung steht — diesmal ohne Rückfrage erlaubt:

```powershell
$env:GIT_TERMINAL_PROMPT = "0"
git ls-remote https://gitea.medialine.com/medialine/claude-plugin-platform.git
```

Erscheint `could not read Username`, fehlt die Anmeldung noch (Schritt 3). Erscheint `not found`, fehlt die Aufnahme in die Organisation (Schritt 2).

---

## 3. Installation

### 3.1 Empfohlen: pro Repository, automatisch

Jedes Medialine-Repository enthält eine eingecheckte `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "medialine": {
      "source": {
        "source": "git",
        "url": "https://gitea.medialine.com/medialine/claude-plugin-platform.git"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "medialine-platform@medialine": true
  }
}
```

Beim ersten Öffnen des Ordners fragt Claude Code, ob dem Verzeichnis vertraut wird, installiert anschließend den Marketplace `medialine` und aktiviert das Plugin beim Session-Start.

> **Achtung:** Der Wert für `source` lautet `"git"`. Ein vereinzelt anzutreffendes `"source": "url"` ist ungültig und verhindert die Installation.

### 3.2 Manuell

```text
/plugin marketplace add https://gitea.medialine.com/medialine/claude-plugin-platform.git
/plugin install medialine-platform@medialine
```

In der VS-Code-Erweiterung stehen diese Unterbefehle **nicht** als Eingabe zur Verfügung. Dort wird das Panel `/plugin` geöffnet und im Reiter **Marketplaces** gearbeitet.

### 3.3 Installation prüfen

```text
/plugin
```

Das Plugin muss unter **INSTALLED** als `medialine-platform@medialine` erscheinen.

> Mehrfachnennungen sind normal und kein Fehler. Es gibt einen Eintrag pro Scope: Ein `user`-Eintrag gilt global, zusätzlich entsteht pro Repository mit eigener `.claude/settings.json` ein `project`-Eintrag. Alle verweisen auf dieselbe Installation.

---

## 4. Aktualisieren

### 4.1 Der wichtigste Punkt

**Plugins werden beim Session-Start geladen.** Eine laufende Session behält die Version, mit der sie gestartet ist, auch wenn auf der Festplatte längst eine neuere liegt. Nach jedem Update daher das **VS-Code-Fenster neu laden** (`Developer: Reload Window`) oder eine neue Session starten.

### 4.2 Update auslösen

Claude Code CLI:

```text
/plugin marketplace update medialine
/plugin update medialine-platform@medialine
```

VS-Code-Erweiterung: Panel `/plugin` → Reiter **Marketplaces** → Marketplace `medialine` aktualisieren.

### 4.3 Was `autoUpdate` tatsächlich tut

`autoUpdate: true` aktualisiert den **Marketplace-Klon**, nicht die **installierte Kopie**. Beides kann auseinanderlaufen: Der Klon ist aktuell, die Installation bleibt alt. Deshalb sind beide Befehle aus 4.2 nötig — der erste holt den Stand, der zweite installiert ihn.

### 4.4 Installierte Version prüfen

Die Versionsnummer allein ist **kein** verlässlicher Nachweis. Zwei Installationen können dieselbe Nummer tragen und unterschiedlichen Inhalt haben:

```bash
diff -rq ~/.claude/plugins/marketplaces/medialine/medialine-platform \
         ~/.claude/plugins/cache/medialine/medialine-platform/<version>
```

Außer der Markierung `.in_use` darf nichts abweichen.

---

## 5. Inhalt des Plugins

### 5.1 Rules, immer aktiv

| Rule | Inhalt |
|---|---|
| `medialine-stack` | Freigegebener Technologie-Stack. Alternativen sind nicht zulässig. |
| `branch-workflow` | Kein direkter Push auf `main`. Jede Änderung auf einem frischen Branch von `origin/main`, Merge ausschließlich per PR. |
| `cloud-only` | Kein lokales `docker compose`. Änderungen gehen über Gitea, Jenkins und Prod. |
| `conventional-commits` | Format `type(scope): beschreibung`. |
| `documentation` | Vor jedem Commit prüfen, ob die Doku angepasst werden muss. |
| `app-baseline` | Jede neue App bringt SSO, Pulse-Widget, KI-Assistent und ein `docs/`-Verzeichnis mit. |
| `security` | Keine Secrets im Code, Pydantic-Validierung, kein `CORS: *`. |
| `feedback-loop` | Lücken im Plugin per `propose_update` zurückmelden. |

### 5.2 Skills, bei Bedarf

| Skill | Wofür |
|---|---|
| `platform-services` | **Übersicht aller gemeinsamen Dienste.** Einstiegspunkt bei neuen Apps und neuen Features. |
| `vibes-conventions` | VIBES v3: Projektstruktur, Namensgebung, Standards. |
| `auth-integration` | TaskTool-SSO und JWT-Anbindung. |
| `pulse-feedback` | Feedback-Widget einbinden und App in Pulse registrieren. |
| `ai-assistant` | Plattform-KI-Assistent einbinden: Widget, Manifest, Tool-Callbacks. |
| `object-storage` | Gemeinsames MinIO nutzen. |
| `vector-search` | Semantische Suche und RAG über den Vector-Service. |
| `cloud-workflow` | Der Cloud-Entwicklungszyklus im Detail. |
| `jenkins-pipeline` | Jenkins-Jobs und Gitea-Webhooks einrichten. |
| `port-allocation` | Port-Vergabe und aktuelles Register. |
| `medialine-dev-credentials` | Tokens erzeugen, erneuern, zurückziehen. |

### 5.3 Agents

`backend-developer` · `frontend-developer` · `integrator` · `reviewer`

Der `reviewer` prüft ein Projekt gegen sämtliche Konventionen und meldet Abweichungen. Das ist vor einem größeren PR nützlich.

### 5.4 Hooks

| Hook | Auslöser | Verhalten |
|---|---|---|
| `block-host-installs` | `pip install`, `npm install` und Ähnliches | **Blockiert.** Abhängigkeiten gehören in `requirements.txt` beziehungsweise `package.json`. |
| `docs-review-gate` | `git commit` mit Code-, aber ohne Doku-Änderungen | **Erinnert**, blockiert nicht. Unterdrückung über die Zeile `Docs-Reviewed: none-needed` in der Commit-Nachricht. |
| `platform-baseline-notice` | Session-Start | Weist einmalig darauf hin, welche Plattformdienste die App noch nicht nutzt. |

### 5.5 MCP-Server

`medialine-diag` · `medialine-gitea` · `medialine-jenkins` · `medialine-plugin` · `medialine-registry` · `medialine-ext-api`

Alle benötigen `MEDIALINE_MCP_TOKEN`, siehe Abschnitt 2.2.

---

## 6. Nutzung im Alltag

Für Rules und Skills ist **keine besondere Bedienung nötig**. Rules gelten automatisch, Skills werden von Claude anhand des Gesprächskontexts herangezogen.

- „Bau eine neue App für X" → `app-baseline` und `platform-services` greifen, Claude richtet SSO, Pulse und Assistent mit ein.
- „Nutzer sollen Feedback geben können" → `pulse-feedback` wird geladen, statt ein eigenes Formular zu bauen.
- „Wo liegen die Logs von klar auf Prod?" → Zugriff über `medialine-diag`.
- „Öffne einen PR" → `branch-workflow` sorgt für einen frischen Branch und den PR gegen `main`.

Ein Skill lässt sich auch ausdrücklich anfordern: „Nutze den Skill `ai-assistant`."

---

## 7. Claude Desktop

Claude Desktop verhält sich **anders als Claude Code**:

1. **Marketplace-Quellen.** Beim Hinzufügen über die Oberfläche werden nur `github.com`, `gitlab.com` und `bitbucket.org` akzeptiert. Ein Gitea-Repository lässt sich auf diesem Weg nicht eintragen.
2. **MCP-Server.** Remote-MCP-Server können **nicht selbst** hinzugefügt werden. Sie sind ausschließlich über eine administrative Bereitstellung verfügbar — siehe [admin-guide.md](./admin-guide.md#5-claude-desktop-bereitstellen).

Skills, Rules, Agents und Slash-Commands funktionieren. Die sechs MCP-Server stehen ohne administrative Bereitstellung nicht zur Verfügung.

> **Typische Fehlermeldung:**
> „Registrierung beim Anmeldedienst von medialine-gitea fehlgeschlagen … OAuth Client ID in den Connector-Einstellungen hinzufügen."
>
> Diese Meldung führt in die Irre. Die Server verwenden **kein** OAuth, es gibt also keine Client-ID, die sich eintragen ließe. Ursache ist in aller Regel ein fehlender oder ungültiger `MEDIALINE_MCP_TOKEN` oder die oben genannte Einschränkung.

---

## 8. Fehlerbehebung

| Symptom | Ursache | Abhilfe |
|---|---|---|
| Marketplace lässt sich nicht hinzufügen | Keine VPN-Verbindung | `nslookup gitea.medialine.com` prüfen |
| `unable to get password from user` beim Hinzufügen | Git hat noch keine gespeicherte Gitea-Anmeldung. Umgebungsvariablen helfen hier nicht | Einmal `git ls-remote …` im Terminal, Browser-Anmeldung, siehe 2.3 |
| Repository `not found`, obwohl angemeldet | Konto ist noch nicht in der Organisation `medialine` | Admin bittet um die Rolle `developer`, siehe 2.3 |
| MCP-Server melden Fehler, OAuth-Meldung erscheint | `MEDIALINE_MCP_TOKEN` fehlt oder ist ungültig | Token setzen, VS Code **vollständig** neu starten |
| Token gesetzt, dennoch Fehler | Variable ist im gestarteten Prozess nicht bekannt | Neue PowerShell über das Startmenü öffnen und `$env:MEDIALINE_MCP_TOKEN.Length` prüfen |
| Neue Skills fehlen nach dem Update | Session hält den alten Stand | Fenster neu laden |
| Plugin erscheint mehrfach | Ein Eintrag pro Scope | Kein Fehler, siehe 3.3 |
| Änderung ist gemergt, wirkt aber nicht | Version wurde nicht erhöht | Beim DRI melden, siehe [admin-guide.md](./admin-guide.md#4-release-und-versionierung) |
| `pip install` wird abgewiesen | `cloud-only`-Hook | Abhängigkeit eintragen, committen, pushen |

---

## 9. Mitwirken

### 9.1 Lücken melden

Fällt in einer Session auf, dass ein Skill nicht mehr der Realität entspricht oder ganz fehlt, meldet Claude dies über `mcp-plugin.propose_update` zurück. Daraus entsteht ein Entwurfs-PR, den der DRI sichtet. Claude fragt vorher um Zustimmung.

### 9.2 Änderungen einbringen

1. Frischen Branch von `origin/main` erstellen. **Niemals** einen bereits gemergten Branch weiterverwenden.
2. PR gegen `main` öffnen und den Jenkins-Build abwarten.
3. **Version erhöhen**, sobald etwas unter `medialine-platform/` geändert wurde — auch bei reinen Dokumentationsänderungen. Ohne Erhöhung erreicht der Inhalt **keine einzige** Installation. Details im [admin-guide.md](./admin-guide.md#4-release-und-versionierung).
4. Squash-Merge über die Gitea-Oberfläche.

---

## 10. Weiterführend

- Betrieb und Release: [admin-guide.md](./admin-guide.md)
- Repository: <https://gitea.medialine.com/medialine/claude-plugin-platform>
- Claude Code Plugins: <https://code.claude.com/docs/en/plugins>
- Zugangsdaten: <https://tasktool.medialine.com/dev/me/credentials>
