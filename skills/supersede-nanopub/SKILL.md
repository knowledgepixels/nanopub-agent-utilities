---
name: supersede-nanopub
description: Replace attribute values in a nanopublication, then sign and publish the updated nanopub as a superseding version
argument-hint: [nanopub-url-or-id]
---

Help the user update a nanopublication by replacing specific RDF attribute values (predicate–object pairs) in its assertion, provenance, or pubinfo graphs, then publishing a new nanopub that supersedes the original.

## Workflow

### 1. Identify the nanopub

The user provides one of:
- A full nanopub URL (trusty URI), e.g. `https://w3id.org/np/RAxxxxx`
- A short trusty ID, e.g. `RAxxxxx`

If the argument is `$ARGUMENTS`, use that as the starting point.

### 2. Fetch and display the existing nanopub

Fetch via HTTP GET with `Accept: application/trig`:

```bash
curl -s -L -H "Accept: application/trig" "<nanopub-url>"
```

Display:
- The nanopub URI
- The full TriG content
- A summary of the named graphs and their key attribute values

### 3. Check the user's profile

Before creating the TriG file, read `~/.nanopub/profile.yaml` to get the user's ORCID:

```bash
cat ~/.nanopub/profile.yaml
```

If `orcid_id` is missing or empty, warn the user: without it, the `sign` command will omit `npx:signedBy` from the signature, which makes the nanopub unlinked from a person. Ask the user to add their ORCID to the profile before proceeding.

### 4. Confirm the desired changes

Show the user the existing attribute values and ask which ones to replace. For each change, confirm:
- **Graph**: which named graph contains the triple (assertion, provenance, or pubinfo)
- **Predicate**: the property to change
- **Old value**: the current object value (shown from the fetched nanopub)
- **New value**: what the user wants it replaced with (literal or IRI)

Multiple attributes can be changed in one go — collect all changes before proceeding.

### 5. Create the TriG file

Write the updated nanopub directly as a TriG file in `tmp/`. Use a placeholder base URI with a trailing slash — the `sign` command will replace it with the trusty URI everywhere.

Start from the fetched TriG and apply the confirmed changes:
- Replace each targeted predicate–object pair with the new value
- Update `dct:created` to the current UTC timestamp (e.g. `"2025-01-15T12:00:00Z"^^xsd:dateTime`)
- Use the user's ORCID (from `~/.nanopub/profile.yaml`) for `prov:wasAttributedTo` and `dct:creator`. Do **not** copy the original author's ORCID.
- Replace the original trusty URI throughout with the temp placeholder (`http://purl.org/nanopub/temp/np001/`)
- Add `npx:supersedes <original-trusty-uri>` in pubinfo, keeping it pointing to the **original** URI

Template structure:

```turtle
@prefix this: <http://purl.org/nanopub/temp/np001/> .
@prefix sub: <http://purl.org/nanopub/temp/np001/> .
@prefix np: <http://www.nanopub.org/nschema#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix npx: <http://purl.org/nanopub/x/> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix orcid: <https://orcid.org/> .
@prefix prov: <http://www.w3.org/ns/prov#> .
# ... copy all other prefixes from the original nanopub ...

sub:Head {
  this: a np:Nanopublication ;
    np:hasAssertion sub:assertion ;
    np:hasProvenance sub:provenance ;
    np:hasPublicationInfo sub:pubinfo .
}

sub:assertion {
  # ... assertion triples with changes applied ...
}

sub:provenance {
  sub:assertion prov:wasAttributedTo orcid:USER-ORCID .
}

sub:pubinfo {
  this: dct:created "TIMESTAMP"^^xsd:dateTime ;
    dct:creator orcid:USER-ORCID ;
    # ... other pubinfo triples from original ...
    npx:supersedes <original-trusty-uri> .
}
```

### 6. Sign

First, ensure the nanopub CLI jar is available. If not already present, download the latest release from Maven Central:

```bash
NP_VERSION=$(curl -s "https://repo1.maven.org/maven2/org/nanopub/nanopub/maven-metadata.xml" | grep -o '<release>[^<]*</release>' | sed 's/<[^>]*>//g')
JAR="nanopub-${NP_VERSION}-jar-with-dependencies.jar"
if [ ! -f "$JAR" ]; then
  curl -L -o "$JAR" "https://repo1.maven.org/maven2/org/nanopub/nanopub/${NP_VERSION}/${JAR}"
fi
java -jar "$JAR" sign -o tmp/<name>-signed.trig tmp/<name>.trig
```

**After signing, always verify** that `npx:signedBy` is present before publishing:

```bash
grep "signedBy" tmp/<name>-signed.trig
```

If `npx:signedBy` is absent, the user's ORCID was not found in the profile. Stop, ask the user to add it to `~/.nanopub/profile.yaml`, and re-sign.

### 7. Test query template nanopubs before publishing

If the nanopub contains a grlc query template (i.e. has a `grlc:sparql` predicate in its assertion), **always test it before publishing.** Use the `_nanopub_trig` parameter on a live Nanopub Query instance to preview and execute the query without publishing.

```bash
# Base64url-encode the signed nanopub
NP_B64=$(base64 -w0 tmp/<name>-signed.trig | tr '+/' '-_' | tr -d '=')

# Extract the artifact code from the signed file
ARTIFACT=$(head -1 tmp/<name>-signed.trig | grep -oP 'RA[A-Za-z0-9_-]{43}')

# Test via the API (replace <query-local-name> with the query's local name)
curl -s "https://query.knowledgepixels.com/api/${ARTIFACT}/<query-local-name>?<param>=<value>&_nanopub_trig=${NP_B64}"
```

You can also open it in the OpenAPI UI for interactive testing:

```
https://query.knowledgepixels.com/openapi/?url=spec/${ARTIFACT}/<query-local-name>&_nanopub_trig=${NP_B64}
```

Verify the results look correct before proceeding to publish. If the query returns errors or unexpected results, go back and fix the TriG file and re-sign.

### 8. Ask about publishing target, then publish

Ask: **test server or live network?**

```bash
# Test server
java -jar $JAR publish --server https://test.registry.knowledgepixels.com/ tmp/<name>-signed.trig

# Live network
java -jar $JAR publish tmp/<name>-signed.trig
```

### 9. Retract the old nanopub (optional)

`npx:supersedes` signals that the new nanopub replaces the old one, but the old nanopub remains accessible. Ask the user if they also want to retract the original:

```bash
java -jar $JAR retract -i <old-nanopub-uri> -p
```

The `-p` flag publishes the retraction immediately.

### 10. Report result

Show:
- The new nanopub trusty URI
- Confirmation that `npx:supersedes <original-uri>` is declared
- If retracted: confirm retraction of the original

## Important Notes

- **Never write a Java class** for one-off nanopub creation. Always create the TriG file directly and use the CLI jar.
- Download the CLI jar from Maven Central if not present (see step 6); reuse it across invocations by keeping it in the working directory.
- Nanopubs use **trusty URIs** — the `sign` command computes and replaces the placeholder URI everywhere in the file.
- The temp URI must end with `/` so sub-resources are correctly derived and transformed.
- Never copy the original nanopub's author ORCID into `dct:creator`/`prov:wasAttributedTo` — always use the current user's ORCID from their profile.
- Never copy the original `dct:created` timestamp — always use the current UTC time.
- If a bad nanopub was published (e.g. missing `npx:signedBy`), retract it with `retract -i <uri> -p` before publishing the corrected version.
- Preserve all prefixes and RDF triples from the original nanopub that are not being changed, to avoid data loss.
