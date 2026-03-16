---
name: modify-query-template
description: Modify a nanodash query template nanopublication — add or remove SPARQL parameters, then sign and publish the updated query as a new nanopub
argument-hint: [query-nanopub-url-or-id]
---

Help the user modify a grlc-style query nanopublication from https://nanodash.knowledgepixels.com/query (or any query.knowledgepixels.com / query.petapico.org endpoint).

## Workflow

### 1. Identify the query

The user provides one of:
- A full nanopub URL (trusty URI), e.g. `https://w3id.org/np/RAxxxxx`
- A query API ID, e.g. `RAxxxxx.../query-name`
- A human-readable name — search `https://query.knowledgepixels.com/` to find matching queries

If the argument is `$ARGUMENTS`, use that as the starting point.

### 2. Fetch and display the existing query nanopub

Fetch via HTTP GET with `Accept: application/trig`:

```bash
curl -s -L -H "Accept: application/trig" "<nanopub-url>"
```

Display:
- The nanopub URI
- The SPARQL query text (look for `grlc:sparql` predicate with a literal value)
- Any implicit grlc parameters: variables prefixed `?__` in the SPARQL are treated as query parameters
- Any explicit parameter RDF triples (e.g. typed as `schema:PropertyValueSpecification`)

### 3. Check the user's profile

Before creating the TriG file, read `~/.nanopub/profile.yaml` to get the user's ORCID:

```bash
cat ~/.nanopub/profile.yaml
```

If `orcid_id` is missing or empty, warn the user: without it, the `sign` command will omit `npx:signedBy` from the signature, which makes the nanopub unlinked from a person. Ask the user to add their ORCID to the profile before proceeding.

### 4. Confirm the desired change

Ask the user:
- Which parameter to **remove** (by variable name), OR
- What **new parameter** to add: name, description, default value (optional), required or optional, type (literal/IRI)
- The new query **name** (used as `rdfs:label` and as the local name in the query API URL)

Also confirm:
- **Supersedes or independent?** Ask explicitly:
  > "Should the new query supersede the original (linked via `npx:supersedes`), or exist as a standalone independent query?"
  - **Supersedes** — the new nanopub declares `npx:supersedes <originalURI>` in its pubinfo, signalling that it replaces the original
  - **Independent** — no link to the original; the new nanopub stands on its own

### 5. Modify the SPARQL

**To remove a parameter (`?__paramName`):**
- Remove `?__paramName` from the `SELECT` clause (including any `(?__paramName as ?alias)` expression)
- Remove any triple pattern that binds `?__paramName` in the `WHERE` clause
- Adapt any `FILTER` that references `?__paramName` — either drop it or generalise it (e.g. a key-specific invalidation filter can become `filter not exists { ?npx npx:invalidates ?np }`)

**To add a parameter:**
- Add `?__paramName` to the `SELECT` clause
- Add a triple pattern or FILTER in `WHERE` that uses `?__paramName`

### 6. Create the TriG file

Write the nanopub directly as a TriG file in `tmp/`. Use a placeholder base URI with a trailing slash — the `sign` command will replace it with the trusty URI everywhere.

Use the local name of the query (lowercase, hyphenated) as the query resource sub-IRI.

Use the user's ORCID (from `~/.nanopub/profile.yaml`) for `prov:wasAttributedTo` and `dct:creator`. Do **not** copy the original author's ORCID.

Template:

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
@prefix grlc: <https://w3id.org/kpxl/grlc/> .

sub:Head {
  this: a np:Nanopublication ;
    np:hasAssertion sub:assertion ;
    np:hasProvenance sub:provenance ;
    np:hasPublicationInfo sub:pubinfo .
}

sub:assertion {
  sub:query-local-name a grlc:grlc-query ;
    dct:description "..." ;
    dct:license <http://www.apache.org/licenses/LICENSE-2.0> ;
    rdfs:label "..." ;
    grlc:endpoint <...> ;
    grlc:sparql """...""" .
}

sub:provenance {
  sub:assertion prov:wasAttributedTo orcid:USER-ORCID .
}

sub:pubinfo {
  this: dct:created "TIMESTAMP"^^xsd:dateTime ;  # ← replace with current UTC time: run `date -u +"%Y-%m-%dT%H:%M:%SZ"`
    dct:creator orcid:USER-ORCID ;
    dct:license <https://creativecommons.org/licenses/by/4.0/> ;
    npx:embeds sub:query-local-name ;
    npx:wasCreatedAt <https://nanodash.knowledgepixels.com/> .
    # only if supersedes:
    # npx:supersedes <original-nanopub-uri> .
}
```

### 7. Sign

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

### 8. Test the query before publishing

**Always test a query template nanopub before publishing.** Use the `_nanopub_trig` parameter on a live Nanopub Query instance to preview and execute the query without publishing it first.

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

Verify the results look correct before proceeding to publish. If the query returns errors or unexpected results, go back and fix the SPARQL, re-create the TriG file, and re-sign.

### 9. Ask about publishing target, then publish

Ask: **test server or live network?**

```bash
# Test server
java -jar $JAR publish --server https://test.registry.knowledgepixels.com/ tmp/<name>-signed.trig

# Live network
java -jar $JAR publish tmp/<name>-signed.trig
```

### 10. Retract the old nanopub (if supersedes or if a bad version was published)

```bash
java -jar $JAR retract -i <old-nanopub-uri> -p
```

The `-p` flag publishes the retraction immediately.

### 11. Report result

Show:
- The new nanopub trusty URI
- The new query API URL: `https://query.knowledgepixels.com/api/<trusty-id>/<query-local-name>`
- If supersedes: confirm retraction of the original
- If independent: note that the new query has no link to the original

## Important Notes

- **Never write a Java class** for one-off nanopub creation. Always create the TriG file directly and use the CLI jar.
- Download the CLI jar from Maven Central if not present (see step 7); reuse it across invocations by keeping it in the working directory.
- Query nanopubs use **trusty URIs** — the `sign` command computes and replaces the placeholder URI everywhere in the file.
- The temp URI must end with `/` so sub-resources like `sub:query-local-name` are correctly derived and transformed.
- Never copy the original nanopub's author ORCID into `dct:creator`/`prov:wasAttributedTo` — always use the current user's ORCID from their profile.
- If a bad nanopub was published (e.g. missing `npx:signedBy`), retract it with `retract -i <uri> -p` before publishing the corrected version.
- The grlc implicit parameter convention: variables prefixed `?__` in SPARQL are treated as injectable query parameters by the grlc API.
