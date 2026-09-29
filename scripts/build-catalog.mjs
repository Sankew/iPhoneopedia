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

const list = (v) => (v == null ? [] : [v].flat())
const natural = (a, b) => a.localeCompare(b, 'en', { numeric: true })
const gb = (s) => parseFloat(s) * (/TB/i.test(s) ? 1024 : 1)

// "iPhone 4 (GSM, 2012)" → "iPhone 4", but "iPhone SE (2nd generation)" stays.
export const modelName = (deviceName) => deviceName.replace(/ \((?![^)]*generation)[^)]*\)$/, '')
export const slug = (name) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// One entry per marketing model; AppleDB has one file per hardware identifier.
export function fromAppleDB(devices) {
  const byName = Map.groupBy(devices, (d) => modelName(d.name))
  return [...byName].map(([name, ds]) => {
    const memory = ds.flatMap((d) => list(d.info)).filter((i) => i.type === 'Memory')
    const ends = ds.map((d) => list(d.discontinued).sort().at(-1))
    return {
      name,
      identifiers: ds.map((d) => d.identifier).sort(natural),
      released: ds.flatMap((d) => list(d.released)).sort()[0],
      discontinued: ends.every(Boolean) ? ends.sort().at(-1) : undefined,
      chip: ds[0].soc,
      // Two-tone finishes have [back, front] hex values; the color name describes the back.
      colors: [...new Map(ds.flatMap((d) => list(d.colors)).map((c) => [c.name, { name: c.name, hex: list(c.hex)[0] }])).values()],
      modelNumbers: [...new Set(ds.flatMap((d) => list(d.model)))].sort(natural),
      storage: [...new Set(memory.flatMap((i) => list(i.Storage)))].sort((a, b) => gb(a) - gb(b)),
      ram: memory.map((i) => i.RAM).find(Boolean),
    }
  })
}

// Generated sections; an override section with the same title replaces the generated one.
export function specsFor(m, o = {}) {
  const hardware = [
    ['Chip', m.chip],
    o.displayInches && ['Display', `${o.displayInches}-inch`],
    m.ram && ['RAM', m.ram],
    m.storage.length && ['Storage', m.storage.join(', ')],
  ].filter(Boolean)
  const generated = [
    { title: 'Hardware', rows: hardware },
    { title: 'Identifiers', rows: [['Model identifiers', m.identifiers.join(', ')], ['Model numbers', m.modelNumbers.join(', ')]] },
  ]
  const custom = o.specs ?? []
  return [...generated.filter((g) => !custom.some((c) => c.title === g.title)), ...custom]
}

const text = (html) =>
  html.replace(/<[^>]+>/g, ' ').replace(/&nbsp;|&#160;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim()

// ponytail: regex over Apple's markup (one heading + image + model numbers per model).
// If Apple redesigns the page and matches drop, the images-dropped check fails the run; swap in an HTML parser then.
export function imagesFromApplePage(html, models, pageURL = APPLE_PAGE) {
  const found = {}
  for (const section of html.split(/<h[23][^>]*>/i).slice(1)) {
    const heading = modelName(text(section.slice(0, section.search(/<\/h[23]>/i))))
    const src = section.match(/<img[^>]*?\s(?:data-src|src|srcset)="([^"\s]+)/i)?.[1]
    if (!src) continue
    const numbers = new Set(section.match(/\bA\d{4}\b/g) ?? [])
    const model =
      models.find((m) => m.name === heading) ?? models.find((m) => m.modelNumbers.some((n) => numbers.has(n)))
    if (model && !found[model.name]) found[model.name] = new URL(src.replace(/&amp;/g, '&'), pageURL).href
  }
  return found
}

export function validate(models, prev, overrides) {
  const problems = []
  const dupes = (xs) => [...new Set(xs.filter((x, i) => xs.indexOf(x) !== i))]
  for (const id of dupes(models.map((m) => m.id))) problems.push(`duplicate id ${id}`)
  for (const id of dupes(models.flatMap((m) => m.identifiers))) problems.push(`identifier ${id} in two models`)
  for (const m of models) {
    if (!m.identifiers.length) problems.push(`${m.name}: no identifiers`)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(m.released ?? '')) problems.push(`${m.name}: bad released date`)
    if (m.imageURL && !m.imageURL.startsWith('https://')) problems.push(`${m.name}: image is not https`)
    for (const c of m.colors ?? []) if (!/^[0-9A-F]{6}$/i.test(c.hex)) problems.push(`${m.name}: bad hex for ${c.name}`)
    for (const k of ['launchPriceUSD', 'displayInches'])
      if (m[k] != null && !(typeof m[k] === 'number' && m[k] > 0)) problems.push(`${m.name}: bad ${k}`)
    for (const s of m.specs)
      for (const r of s.rows)
        if (r.length !== 2 || r.some((v) => typeof v !== 'string' || !v)) problems.push(`${m.name}: bad row in ${s.title}`)
  }
  for (const key of Object.keys(overrides))
    if (!models.some((m) => m.id === slug(key))) problems.push(`override "${key}" matches no model`)
  if (models.length < prev.models.length) problems.push(`model count dropped ${prev.models.length} → ${models.length}`)
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
  return readdirSync(folder).map((f) => JSON.parse(readFileSync(join(folder, f), 'utf8')))
}

const get = (url, init) => fetch(url, { ...init, headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(20_000) })

async function wikiSummary(title) {
  const res = await get(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title.replaceAll(' ', '_'))}`)
  if (!res.ok) return void (res.status !== 404 && console.warn(`Wikipedia ${title}: HTTP ${res.status}`))
  const page = await res.json()
  return page.type === 'standard' && page.extract ? { about: page.extract, aboutSource: page.content_urls?.desktop?.page } : undefined
}

async function main() {
  const prev = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : { models: [] }
  const prevByID = new Map(prev.models.map((m) => [m.id, m]))
  const overrides = JSON.parse(readFileSync(OVERRIDES, 'utf8'))
  const base = fromAppleDB(loadAppleDB(process.argv[2]))

  // Network sources are best-effort: on failure keep the previous catalog's values; validation catches regressions.
  const images = await get(APPLE_PAGE)
    .then((r) => (r.ok ? r.text() : Promise.reject(new Error(`HTTP ${r.status}`))))
    .then((html) => imagesFromApplePage(html, base))
    .catch((e) => (console.warn(`Apple page skipped: ${e.message}`), {}))

  const models = []
  for (const b of base) {
    const o = overrides[b.name] ?? {}
    const p = prevByID.get(slug(b.name)) ?? {}
    const wiki = o.about
      ? { about: o.about, aboutSource: o.aboutSource }
      : ((await wikiSummary(o.wiki ?? b.name).catch((e) => console.warn(`Wikipedia ${b.name}: ${e.message}`))) ??
        { about: p.about, aboutSource: p.aboutSource })
    models.push({
      id: slug(b.name),
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

  const problems = validate(models, prev, overrides)
  if (problems.length) {
    console.error(`Catalog not written:\n- ${problems.join('\n- ')}`)
    process.exit(1)
  }
  // Stable output: only a real content change rewrites the file (and bumps generatedAt).
  if (JSON.stringify(models) === JSON.stringify(prev.models)) return console.log(`Unchanged (${models.length} models).`)
  const catalog = { schemaVersion: 1, generatedAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), models }
  writeFileSync(OUT, JSON.stringify(catalog, null, 2) + '\n')
  console.log(`Wrote ${OUT}: ${models.length} models, ${models.filter((m) => m.imageURL).length} with images.`)
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main()
