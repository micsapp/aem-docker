# Content Fragment Model Fix

## Problem

On a local AEM author, the Content Fragment Models console at
`http://localhost:4502/libs/dam/cfm/models/console/content/models.html/conf/<config-name>`
does not show a **Create** button. As a result, no Content Fragment Models can be authored, which in turn blocks creating any Content Fragments.

## Symptom

- AEM Author and the Content Fragment Management OSGi bundles are healthy and running.
- The model console renders but the toolbar is empty (no Create / no actions).
- Logs may show warnings like `Config Id must not be null` while loading the models console.

## Cause

The Content Fragment Models feature requires a specific JCR tree under the configuration's `settings/dam/cfm/models` path:

| Path | Required primary type |
|---|---|
| `/conf/<config-name>/settings/dam/cfm/models` | `nt:folder` |
| `/conf/<config-name>/settings/dam/cfm/models/formbuilderconfig` | `sling:Folder` |

This is the same structure AEM ships under `/libs/settings/dam/cfm/models`.

Two common ways this breaks:

1. **Configuration created without the CFM capability enabled.** Both the `global` configuration (out of the box on a fresh local SDK) and project configurations created by the AEM Project Archetype tend to land *without* the Content Fragment Models capability ticked. The archetype in particular creates `/conf/<project>/settings/dam/cfm/models` as a `cq:Page` placeholder — wrong primary type, no `formbuilderconfig` child, so the console refuses to show Create.
2. **Missing entirely.** The `cfm/models` subtree never got created under `/conf/<config-name>/settings/dam/`.

Either case is fixed by getting the right structure in place under the target configuration.

## Resolution — pick one of three paths

The three paths all produce the same end state. Pick by environment / preference.

### Path 1 — Configuration Browser (recommended, UI)

This is the screen Adobe designed for enabling per-configuration features like Content Fragment Models. AEM creates the right JCR structure for you when you tick the box.

1. Log in to AEM author at `http://localhost:4502` (`admin` / `admin`).
2. Top hat menu → **Tools** → **General** → **Configuration Browser**.
   Direct URL: `http://localhost:4502/libs/granite/configurations/content/jcrtypes/configurations.html`
3. Single-click the target configuration (e.g. `global` or `spa-mvn`) to select it — do not double-click.
4. Click **Properties** in the top action bar.
5. In the dialog, tick **Content Fragment Models** (and **Content Fragments** if not already on).
6. **Save & Close**.
7. Reload the model console at `http://localhost:4502/libs/dam/cfm/models/console/content/models.html/conf/<config-name>` — the **Create** button now appears.

### Path 2 — CRX/DE Lite (UI, manual JCR edit)

Useful as a fallback if the Configuration Browser dialog is unavailable or the checkbox doesn't take effect.

1. `http://localhost:4502/crx/de/index.jsp` — log in as admin / admin.
2. In the left tree, navigate to `/conf/<config-name>/settings/dam/cfm/models`.
3. If that node already exists with the wrong type (e.g. `cq:Page` from the archetype): right-click → **Delete**, then click **Save All** in the top toolbar.
4. Navigate to `/libs/settings/dam/cfm/models`.
5. Right-click → **Copy**.
6. Navigate to `/conf/<config-name>/settings/dam/cfm`.
7. Right-click → **Paste**. A new `models` child is created.
8. Click **Save All**.
9. Reload the model console — Create button appears.

### Path 3 — Three curl commands (CLI)

For scripted / repeatable setup, or to fix multiple configurations at once.

```bash
AEM=http://localhost:4502
AUTH='-u admin:admin'
CONFIG=spa-mvn          # or "global", or your project config

# 1) Make sure the parent /conf/<CONFIG>/settings/dam/cfm exists.
#    Idempotent — re-running on an existing folder is a no-op.
curl -sS $AUTH \
  -F "jcr:primaryType=sling:Folder" \
  "$AEM/conf/$CONFIG/settings/dam/cfm"

# 2) Delete any wrong-typed placeholder at .../cfm/models
#    (the archetype creates this as a cq:Page; we replace it with the correct shape).
#    Safe even if the node doesn't exist.
curl -sS $AUTH -F ":operation=delete" \
  "$AEM/conf/$CONFIG/settings/dam/cfm/models"

# 3) Copy the stock structure from /libs to the configuration.
curl -sS $AUTH \
  -F ":operation=copy" \
  -F ":dest=/conf/$CONFIG/settings/dam/cfm/models" \
  "$AEM/libs/settings/dam/cfm/models"
```

Verify success:

```bash
curl -sS $AUTH "$AEM/conf/$CONFIG/settings/dam/cfm/models.1.json"
# Expect: jcr:primaryType = "nt:folder" with a "formbuilderconfig" child
```

## Verification

After applying any of the three paths, all of the following should be true:

```text
/conf/<config-name>/settings/dam/cfm/models                        nt:folder
/conf/<config-name>/settings/dam/cfm/models/formbuilderconfig     sling:Folder
```

And the model console URL renders a Create action:

```text
http://localhost:4502/libs/dam/cfm/models/console/content/models.html/conf/<config-name>
```

## Notes

- The fix is needed *per configuration*. If you have both `/conf/global` and `/conf/spa-mvn`, apply to whichever one you intend to author models against. Most projects pick one (typically the project-named config) and stick with it.
- To create actual Content Fragments under `/content/dam/<project>/cf/...`, the target Assets folder may also need its `sling:configRef` property set to the configuration that owns the models. From the Assets UI: select the folder → **View Properties** → **Cloud Services** tab → **Configuration** → pick `/conf/<config-name>`. Without this, the "New → Content Fragment" picker will show no models even after the Create button appears in the models console.
- The CFM feature is independent of the rest of the project setup (templates, components, clientlibs). Enabling it on a configuration doesn't break anything else.
