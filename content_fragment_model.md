# Content Fragment Model Fix

## Problem

The local AEM Author instance was running, but Content Fragment Models could not be created from the UI.

The Docker container and AEM runtime were healthy:

- The `aem-author` container was running.
- AEM responded on port `4502`.
- Content Fragment Management and GraphQL bundles were active.

The issue was not Docker. The AEM repository was missing the required Content Fragment Model configuration under:

```text
/conf/global/settings/dam/cfm/models
```

Without this configuration, AEM does not expose the normal model creation flow for the selected configuration. The logs also showed warnings like:

```text
Config Id must not be null
```

This pointed to a missing or incomplete `/conf` configuration.

## Fix Applied

The missing Content Fragment Model configuration was created under the `global` configuration.

First, the parent path was created:

```text
/conf/global/settings/dam/cfm
```

Then the stock Content Fragment Model configuration was copied from:

```text
/libs/settings/dam/cfm/models
```

to:

```text
/conf/global/settings/dam/cfm/models
```

This created the expected model configuration tree, including the required form builder configuration used by the Content Fragment Model editor.

## Verification

After the fix, the model console for the `global` configuration rendered the **Create** action:

```text
http://localhost:4502/libs/dam/cfm/models/console/content/models.html/conf/global
```

The expected repository path now exists:

```text
/conf/global/settings/dam/cfm/models
```

## Notes

This fix enables creating Content Fragment Models under the `Global` configuration.

To create actual Content Fragments under `/content/dam`, the target Assets folder may also need to be associated with the correct configuration in the folder properties.
