#!/usr/bin/env node
// Builds Shared/catalog.json from AppleDB, Apple's "Identify your iPhone model" page,
// Wikipedia summaries and data/overrides.json. Precedence: overrides > scraped > AppleDB.
// Usage: node scripts/build-catalog.mjs [path-to-appledb-checkout]
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const OUT = 'Shared/catalog.json'
const OVERRIDES = 'data/overrides.json'
const APPLE_PAGE = 'https://support.apple.com/en-us/108044'
const UA = 'iPhoneopedia-catalog/1.0 (https://github.com/Sankew/iPhoneopedia)'
// The app loads images and opens source links from these hosts only.
const IMAGE_HOSTS = /(^|\.)(cdn-)?apple\.com$/
const SOURCE_HOSTS = /(^|\.)wikipedia\.org$/

const list = (v) => (v == null ? [] : [v].flat())
const natural = (a, b) => a.localeCompare(b, 'en', { numeric: true })
const gb = (s) => parseFloat(s) * (/TB/i.test(s) ? 1024 : 1)
const isHex = (s) => typeof s === 'string' && /^[0-9A-F]{6}$/i.test(s)
const warn = (message) => console.log(`::warning::${message}`) // GitHub Actions annotation

// "iPhone 4 (GSM, 2012)" → "iPhone 4", but "iPhone SE (2nd generation)" stays.
export const modelName = (deviceName) => deviceName.replace(/ \((?![^)]*generation)[^)]*\)$/, '')
export const slug = (name) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// One entry per marketing model; AppleDB has one file per hardware identifier.
export function fromAppleDB(devices) {
  const byName = Map.groupBy(devices, (d) => modelName(d.name))
  return [...byName].map(([name, ds]) => {
    const memory = ds.flatMap((d) => list(d.info)).filter((i) => i.type === 'Memory')
    const ends = ds.map((d) => list(d.discontinued).sort().at(-1))
    const colors = ds
      .flatMap((d) => list(d.colors))
      // Two-tone finishes have [back, front] hex values; the color name describes the back.
      .map((c) => ({ name: c.name, hex: list(c.hex)[0] }))
      .filter((c) => c.name && isHex(c.hex))
    return {
      name,
      identifiers: ds.map((d) => d.identifier).sort(natural),
      released: ds.flatMap((d) => list(d.released)).sort()[0],
      discontinued: ends.every(Boolean) ? ends.sort().at(-1) : undefined,
      chip: ds[0].soc,
      colors: [...new Map(colors.map((c) => [c.name, c])).values()],
      modelNumbers: [...new Set(ds.flatMap((d) => list(d.model)))].sort(natural),
      storage: [...new Set(memory.flatMap((i) => list(i.Storage)))].sort((a, b) => gb(a) - gb(b)),
      ram: memory.map((i) => i.RAM).find(Boolean),
    }
  })
}

// Generated sections; an override section with the same title replaces the generated one.
export function specsFor(m, o = {}) {
  const rows = (...pairs) => pairs.filter(Boolean)
  const generated = [
    {
      title: 'Hardware',
      rows: rows(
        ['Chip', o.chip ?? m.chip],
        o.displayInches && ['Display', `${o.displayInches}-inch`],
        m.ram && ['RAM', m.ram],
        m.storage.length && ['Storage', m.storage.join(', ')],
      ),
    },
    {
      title: 'Identifiers',
      rows: rows(
        ['Model identifiers', m.identifiers.join(', ')],
        m.modelNumbers.length && ['Model numbers', m.modelNumbers.join(', ')],
      ),
    },
  ]
  const custom = o.specs ?? []
  return [...generated.filter((g) => !custom.some((c) => c.title === g.title)), ...custom]
}

const text = (html) =>
  html.replace(/<[^>]+>/g, ' ').replace(/&nbsp;|&#160;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim()

// A regex over Apple's markup (one heading + image + model numbers per model).
// If Apple redesigns the page, the scrape-hit check in main() fails the run; swap in an HTML parser then.
export function imagesFromApplePage(html, models, pageURL = APPLE_PAGE) {
  const found = {}
  for (const section of html.split(/<h[23][^>]*>/i).slice(1)) {
    const heading = modelName(text(section.slice(0, section.search(/<\/h[23]>/i))))
    const img = section.match(/<img\b[^>]*>/i)?.[0] ?? ''
    const attr = (name) => img.match(new RegExp(`\\s${name}=["']([^"']+)["']`, 'i'))?.[1]
    // Lazy-loaded images keep the real URL in data-src; srcset lists "url 2x, url 3x".
    const src = [attr('data-src'), attr('src'), attr('srcset')?.split(/[\s,]+/)[0]]
      .map((candidate) => {
        try {
          return candidate && new URL(candidate.replace(/&amp;/g, '&'), pageURL)
        } catch {
          return undefined
        }
      })
      .find((url) => url?.protocol === 'https:')
    if (!src) continue
    const numbers = new Set(section.match(/\bA\d{4}\b/g) ?? [])
    const model =
      models.find((m) => m.name === heading) ?? models.find((m) => m.modelNumbers.some((n) => numbers.has(n)))
    if (model && !found[model.name]) found[model.name] = src.href
  }
  return found
}

// Real calendar day: "2026-02-30" parses to March 2nd and "2026-13-45" to NaN, so both fail.
const isDay = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && new Date(`${s}T00:00:00Z`).toJSON()?.startsWith(s) === true
const httpsOn = (url, hosts) => {
  try {
    const u = new URL(url)
    return u.protocol === 'https:' && hosts.test(u.hostname)
  } catch {
    return false
  }
}

// Mirrors the app's Codable types: anything the app can't decode must never be published.
export function validate(models, prev, overrides, sourceNames) {
  const problems = []
  const dupes = (xs) => [...new Set(xs.filter((x, i) => xs.indexOf(x) !== i))]
  for (const id of dupes(models.map((m) => m.id))) problems.push(`duplicate id ${id}`)
  for (const id of dupes(models.flatMap((m) => m.identifiers))) problems.push(`identifier ${id} in two models`)
  for (const m of models) {
    for (const k of ['name', 'chip']) if (typeof m[k] !== 'string' || !m[k]) problems.push(`${m.name}: missing ${k}`)
    if (!m.identifiers?.length) problems.push(`${m.name}: no identifiers`)
    if (!isDay(m.released)) problems.push(`${m.name}: bad released date`)
    if (m.discontinued != null && !(isDay(m.discontinued) && m.discontinued >= m.released))
      problems.push(`${m.name}: bad discontinued date`)
    if (m.launchPriceUSD != null && !(Number.isInteger(m.launchPriceUSD) && m.launchPriceUSD > 0))
      problems.push(`${m.name}: bad launchPriceUSD`)
    if (m.displayInches != null && !(typeof m.displayInches === 'number' && m.displayInches > 0))
      problems.push(`${m.name}: bad displayInches`)
    if (m.imageURL != null && !httpsOn(m.imageURL, IMAGE_HOSTS)) problems.push(`${m.name}: image must be https on apple.com`)
    if (m.aboutSource != null && !httpsOn(m.aboutSource, SOURCE_HOSTS))
      problems.push(`${m.name}: aboutSource must be https on wikipedia.org`)
    for (const c of m.colors) if (!c.name || !isHex(c.hex)) problems.push(`${m.name}: bad color ${c.name}`)
    if (dupes(m.specs.map((s) => s.title)).length) problems.push(`${m.name}: duplicate spec section`)
    for (const s of m.specs) {
      if (dupes(s.rows.map((r) => JSON.stringify(r))).length) problems.push(`${m.name}: duplicate row in ${s.title}`)
      for (const r of s.rows)
        if (r.length !== 2 || r.some((v) => typeof v !== 'string' || !v)) problems.push(`${m.name}: bad row in ${s.title}`)
    }
  }
  for (const key of Object.keys(overrides))
    if (!sourceNames.some((name) => slug(name) === slug(key))) problems.push(`override "${key}" matches no model`)
  // Ids are keyed by users' saved phones, Siri and Spotlight: a published id must never disappear.
  for (const p of prev.models) if (!models.some((m) => m.id === p.id)) problems.push(`${p.name} (${p.id}) disappeared`)
  const images = (ms) => ms.filter((m) => m.imageURL).length
  if (images(models) < images(prev.models)) problems.push(`images dropped ${images(prev.models)} → ${images(models)}`)
  return problems
}

function loadAppleDB(dir) {
  if (!dir) {
    dir = join(mkdtempSync(join(tmpdir(), 'appledb-')), 'appledb')
    const git = (...args) => execFileSync('git', args, { stdio: 'inherit' })
    git('clone', '--depth=1', '--filter=blob:none', '--sparse', 'https://github.com/littlebyteorg/appledb.git', dir)
    git('-C', dir, 'sparse-checkout', 'set', 'deviceFiles/iPhone')
  }
  const folder = join(dir, 'deviceFiles/iPhone')
  return readdirSync(folder)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(folder, f), 'utf8')))
}

const get = (url, init) => fetch(url, { ...init, headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(20_000) })

async function wikiSummary(title) {
  const res = await get(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title.replaceAll(' ', '_'))}`)
  if (!res.ok) return void (res.status !== 404 && warn(`Wikipedia ${title}: HTTP ${res.status}`))
  const page = await res.json()
  return page.type === 'standard' && page.extract ? { about: page.extract, aboutSource: page.content_urls?.desktop?.page } : undefined
}

async function main() {
  const prev = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : { models: [] }
  const prevByID = new Map(prev.models.map((m) => [m.id, m]))
  const overrides = JSON.parse(readFileSync(OVERRIDES, 'utf8'))
  const overrideFor = Object.fromEntries(Object.entries(overrides).map(([key, value]) => [slug(key), value]))
  const base = fromAppleDB(loadAppleDB(process.argv[2]))

  // Network sources are best-effort: on failure keep the previous catalog's values.
  let applePageLoaded = true
  const images = await get(APPLE_PAGE)
    .then((r) => (r.ok ? r.text() : Promise.reject(new Error(`HTTP ${r.status}`))))
    .then((html) => imagesFromApplePage(html, base))
    .catch((e) => {
      applePageLoaded = false
      warn(`Apple page skipped, keeping previous images: ${e.message}`)
      return {}
    })

  const models = []
  for (const b of base) {
    const o = overrideFor[slug(b.name)] ?? {}
    const id = slug(b.identifiers[0]) // hardware identifiers never change; names sometimes do
    const p = prevByID.get(id) ?? {}
    const wiki = o.about
      ? { about: o.about, aboutSource: o.aboutSource }
      : ((await wikiSummary(o.wiki ?? b.name).catch((e) => warn(`Wikipedia ${b.name}: ${e.message}`))) ??
        { about: p.about, aboutSource: p.aboutSource })
    models.push({
      id,
      name: o.name ?? b.name,
      identifiers: b.identifiers,
      released: b.released,
      discontinued: b.discontinued,
      chip: o.chip ?? b.chip,
      tagline: o.tagline,
      launchPriceUSD: o.launchPriceUSD,
      displayInches: o.displayInches,
      imageURL: o.imageURL ?? images[b.name] ?? p.imageURL,
      colors: b.colors,
      specs: specsFor(b, o),
      about: wiki.about,
      aboutSource: wiki.aboutSource,
    })
  }
  models.sort((a, b) => a.released.localeCompare(b.released) || natural(a.name, b.name))

  const problems = validate(models, prev, overrides, base.map((b) => b.name))
  const hits = Object.keys(images).length
  if (applePageLoaded && hits < base.length * 0.8)
    problems.push(`Apple page matched ${hits}/${base.length} models; its markup probably changed`)
  if (problems.length) {
    console.error(`Catalog not written:\n- ${problems.join('\n- ')}`)
    process.exit(1)
  }
  // Stable output: only a real content change rewrites the file (and bumps generatedAt).
  if (JSON.stringify(models) === JSON.stringify(prev.models)) return console.log(`Unchanged (${models.length} models).`)
  const catalog = { schemaVersion: 1, generatedAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), models }
  writeFileSync(OUT, JSON.stringify(catalog, null, 2) + '\n')
  console.log(`Wrote ${OUT}: ${models.length} models, ${models.filter((m) => m.imageURL).length} with images, Apple page matched ${hits}.`)
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main()
