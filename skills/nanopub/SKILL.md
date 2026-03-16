---
name: nanopub
description: Create, sign, publish, query, or retract nanopublications
argument-hint: [nanopub URL, description, or action]
---

Help the user work with nanopublications. This includes creating new nanopubs, fetching and inspecting existing ones, superseding or retracting nanopubs, and publishing to the test server or live network.

## Workflow

### 1. Determine the action

The user may want to:
- **Create** a new nanopub from RDF content, a claim, a shape, or other structured content
- **Fetch/inspect** an existing nanopub by URL or trusty ID
- **Query** nanopubs via Nanopub Query (the grlc-based SPARQL query API)
- **Supersede** an existing nanopub with updated content
- **Retract** a published nanopub

If the argument is `$ARGUMENTS`, use that as the starting point.

#### Fetching an existing nanopub

Fetch via HTTP GET with `Accept: application/trig`:

```bash
curl -s -L -H "Accept: application/trig" "<nanopub-url>"
```

Display the nanopub URI, full TriG content, and a summary of the named graphs.

#### Querying nanopubs via Nanopub Query

Nanopub Query is a grlc-based API that exposes published SPARQL query templates as REST endpoints. The base instance is at `https://query.knowledgepixels.com/`.

**Discovering available queries:**

To list all available queries at the current point in time, use the `get-queries` meta-query:

```bash
curl -s "https://query.knowledgepixels.com/api/RAQqjXQYlxYQeI4Y3UQy9OrD5Jx1E3PJ8KwKKQlWbiYSw/get-queries"
```

This returns all published query templates and can be used as a starting point to find queries relevant to a given task.

**Downloading all query templates locally:**

Run the [download script](scripts/download-queries.sh) to fetch all query template nanopublications as individual TriG files into the [queries/](queries/) folder:

```bash
bash skills/nanopub/scripts/download-queries.sh
```

This is useful for browsing, searching, or analyzing the full set of available queries offline. Files are named `<trusty-id>_<label>.trig`. Re-running the script skips already-downloaded files.

To browse the OpenAPI spec for a specific published query:

```
https://query.knowledgepixels.com/openapi/?url=spec/<ARTIFACT-CODE>/<query-local-name>
```

Where `<ARTIFACT-CODE>` is the trusty ID (e.g. `RAxxx...`) and `<query-local-name>` is the query's local name from the assertion.

**Calling a query via the API:**

```bash
curl -s "https://query.knowledgepixels.com/api/<ARTIFACT-CODE>/<query-local-name>?<param1>=<value1>&<param2>=<value2>"
```

- Parameters correspond to grlc implicit parameters (`?__paramName` variables in the SPARQL)
- The response is typically CSV or JSON depending on the `Accept` header
- Add `Accept: text/csv` for CSV or `Accept: application/json` for JSON results

**Testing an unpublished query template:**

Before publishing a query template nanopub, you can test it by base64url-encoding the signed TriG and passing it as the `_nanopub_trig` parameter:

```bash
# Base64url-encode the signed nanopub
NP_B64=$(base64 -w0 tmp/<name>-signed.trig | tr '+/' '-_' | tr -d '=')

# Extract the artifact code from the signed file
ARTIFACT=$(head -1 tmp/<name>-signed.trig | grep -oP 'RA[A-Za-z0-9_-]{43}')

# Call the API with the encoded nanopub
curl -s "https://query.knowledgepixels.com/api/${ARTIFACT}/<query-local-name>?<param>=<value>&_nanopub_trig=${NP_B64}"
```

Or open the OpenAPI UI for interactive testing:

```
https://query.knowledgepixels.com/openapi/?url=spec/${ARTIFACT}/<query-local-name>&_nanopub_trig=${NP_B64}
```

### 2. Check the user's profile

Before creating the TriG file, read `~/.nanopub/profile.yaml` to get the user's ORCID:

```bash
cat ~/.nanopub/profile.yaml
```

If `orcid_id` is missing or empty, warn the user: without it, the `sign` command will omit `npx:signedBy` from the signature, which makes the nanopub unlinked from a person. Ask the user to add their ORCID to the profile before proceeding.

### 3. Create the TriG file

Write the nanopub directly as a TriG file in `tmp/`. Use a placeholder base URI with a trailing slash — the `sign` command will replace it with the trusty URI everywhere.

Get the current UTC timestamp by running:

```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

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
# ... add any domain-specific prefixes needed for the assertion ...

sub:Head {
  this: a np:Nanopublication ;
    np:hasAssertion sub:assertion ;
    np:hasProvenance sub:provenance ;
    np:hasPublicationInfo sub:pubinfo .
}

sub:assertion {
  # ... assertion triples ...
}

sub:provenance {
  # Use one or both depending on the origin of the assertion content:
  # If content was derived/extracted from an external source:
  # sub:assertion prov:wasDerivedFrom <source-url> .
  # If the user authored the content:
  # sub:assertion prov:wasAttributedTo orcid:USER-ORCID .
  # If both (e.g. user modified content from an external source), include both triples.
}

sub:pubinfo {
  this: dct:created "TIMESTAMP"^^xsd:dateTime ;  # ← replace with current UTC time
    rdfs:label "short human-readable label" ;  # can be omitted if an introduced resource already has an rdfs:label in the assertion
    dct:creator orcid:USER-ORCID ;
    dct:license <https://creativecommons.org/licenses/by/4.0/> .
    # only if the nanopub supersedes an earlier one:
    # npx:supersedes <original-nanopub-uri> .
    # only if the nanopub introduces a new concept/resource as its main element:
    # npx:introduces <main-element-IRI> .
    # only if created at a specific tool instance (e.g. nanodash):
    # npx:wasCreatedAt <https://nanodash.knowledgepixels.com/> .
}
```

### 4. Sign

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

### 5. Test query template nanopubs before publishing

If the nanopub contains a grlc query template (i.e. has a `grlc:sparql` predicate in its assertion), **always test it before publishing** using the unpublished query testing method described in the "Querying nanopubs via Nanopub Query" section above. Verify the results look correct before proceeding to publish.

### 6. Ask about publishing target, then publish

Ask: **test server or live network?**

```bash
# Test server
java -jar $JAR publish --server https://test.registry.knowledgepixels.com/ tmp/<name>-signed.trig

# Live network
java -jar $JAR publish tmp/<name>-signed.trig
```

### 7. Retract a nanopub (if a bad version was published)

```bash
java -jar $JAR retract -i <nanopub-uri> -p
```

The `-p` flag publishes the retraction immediately.

### 8. Report result

Show:
- The new nanopub trusty URI
- If supersedes: confirm the `npx:supersedes` link
- If introduces: note the introduced resource

## Important Notes

- **Never write a Java class** for one-off nanopub creation. Always create the TriG file directly and use the CLI jar.
- Download the CLI jar from Maven Central if not present (see step 4); reuse it across invocations by keeping it in the working directory.
- Nanopubs use **trusty URIs** — the `sign` command computes and replaces the placeholder URI everywhere in the file.
- The temp URI must end with `/` so sub-resources are correctly derived and transformed.
- Never copy the original nanopub's author ORCID into `dct:creator`/`prov:wasAttributedTo` — always use the current user's ORCID from their profile.
- Always get the current UTC time by running `date -u +"%Y-%m-%dT%H:%M:%SZ"` for `dct:created` timestamps. Never use a date-only or zeroed time.
- If a bad nanopub was published (e.g. missing `npx:signedBy`), retract it with `retract -i <uri> -p` before publishing the corrected version.
- Provenance should reflect the actual origin of the assertion content: use `prov:wasDerivedFrom` when content comes from an external source, `prov:wasAttributedTo` when the user authored it, or both when the user modified external content.
- Add `npx:introduces` in pubinfo pointing to the main element of the assertion when the nanopub introduces a new concept or resource (e.g. a new shape, class, or query definition).
- Always add an `rdfs:label` on `this:` in pubinfo with a short human-readable label for the nanopub. This can be omitted only if the nanopub has an introduced resource (via `npx:introduces`) that already has an `rdfs:label` in the assertion graph.
- Only add `npx:wasCreatedAt` if the nanopub was actually created at that specific tool instance. Do not add it by default.
