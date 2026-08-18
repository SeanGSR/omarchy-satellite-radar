#!/usr/bin/env node

const query = String(process.argv[2] || "").trim()
const endpoint = "https://geocoding-api.open-meteo.com/v1/search"

async function search(value) {
  const url = `${endpoint}?name=${encodeURIComponent(value)}&count=10&language=en&format=json`
  const response = await fetch(url, {
    signal: AbortSignal.timeout(6000),
    headers: { "User-Agent": "omarchy-satellite-radar/1.1 (personal desktop widget)" }
  })
  if (!response.ok) throw new Error(`Location search failed (${response.status})`)
  return response.json()
}

async function main() {
  if (!query) return process.stdout.write('{"results":[]}')
  let payload = await search(query)
  if (payload.results && payload.results.length) {
    process.stdout.write(JSON.stringify(payload))
    return
  }

  // Open-Meteo distinguishes some hyphenated place names from the same
  // words separated by spaces. Retry only after an empty result, keeping the
  // normal autocomplete request count low.
  const alternate = query.includes("-")
    ? query.replace(/-+/g, " ")
    : query.replace(/\s+/g, "-")
  if (alternate !== query) payload = await search(alternate)
  process.stdout.write(JSON.stringify(payload))
}

main().catch(error => {
  process.stdout.write(JSON.stringify({ error: String(error.message || error), results: [] }))
})
