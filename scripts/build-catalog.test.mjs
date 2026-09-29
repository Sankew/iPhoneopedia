// Run from the repo root: node --test
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fromAppleDB, imagesFromApplePage, modelName, slug, specsFor, validate } from './build-catalog.mjs'

const iPhone4 = [
  { name: 'iPhone 4 (GSM)', identifier: 'iPhone3,1', soc: 'A4', model: 'A1332', released: ['2010-06-24', '2011-04-28'], discontinued: ['2011-10-04', '2012-09-12'], colors: [{ name: 'Black', hex: '000000' }, { name: 'White', hex: 'EBEBEB' }], info: [{ type: 'Memory', Storage: ['8GB', '16GB', '32GB'], RAM: '512MB LPDDR' }] },
  { name: 'iPhone 4 (GSM, 2012)', identifier: 'iPhone3,2', soc: 'A4', model: 'A1332', released: '2012-09-21', discontinued: '2013-09-10', colors: [{ name: 'Black', hex: '000000' }] },
  { name: 'iPhone 4 (CDMA)', identifier: 'iPhone3,3', soc: 'A4', model: 'A1349', released: '2011-02-10', discontinued: '2012-09-12', colors: [{ name: 'Slate', hex: ['273037', '070707'] }] },
]

test('model names drop region suffixes but keep generations', () => {
  assert.equal(modelName('iPhone 4 (GSM, 2012)'), 'iPhone 4')
  assert.equal(modelName('iPhone XS Max (China mainland)'), 'iPhone XS Max')
  assert.equal(modelName('iPhone SE (2nd generation)'), 'iPhone SE (2nd generation)')
  assert.equal(slug('iPhone SE (2nd generation)'), 'iphone-se-2nd-generation')
})

test('devices merge into one model', () => {
  const [m] = fromAppleDB(iPhone4)
  assert.equal(m.name, 'iPhone 4')
  assert.deepEqual(m.identifiers, ['iPhone3,1', 'iPhone3,2', 'iPhone3,3'])
  assert.equal(m.released, '2010-06-24')
  assert.equal(m.discontinued, '2013-09-10')
  assert.deepEqual(m.colors, [{ name: 'Black', hex: '000000' }, { name: 'White', hex: 'EBEBEB' }, { name: 'Slate', hex: '273037' }])
  assert.deepEqual(m.modelNumbers, ['A1332', 'A1349'])
  assert.deepEqual(m.storage, ['8GB', '16GB', '32GB'])
  const [sold] = fromAppleDB([{ ...iPhone4[0], discontinued: undefined }, iPhone4[2]])
  assert.equal(sold.discontinued, undefined, 'still sold while any variant is')
})

test('override spec sections replace generated ones with the same title', () => {
  const [m] = fromAppleDB(iPhone4)
  const specs = specsFor(m, { displayInches: 3.5, specs: [{ title: 'Identifiers', rows: [['x', 'y']] }, { title: 'Camera', rows: [['Main', '5 MP']] }] })
  assert.deepEqual(specs.map((s) => s.title), ['Hardware', 'Identifiers', 'Camera'])
  assert.deepEqual(specs[0].rows[1], ['Display', '3.5-inch'])
  assert.deepEqual(specs[1].rows, [['x', 'y']])
})

test('Apple page images match by heading, then by model number', () => {
  const models = [...fromAppleDB(iPhone4), { name: 'iPhone 3G', modelNumbers: ['A1241'] }]
  const html = `
    <h1>Identify your iPhone model</h1>
    <h2 class="gb-header">iPhone&nbsp;4</h2><p><img alt="" src="/library/iphone4.png"></p><p>Model number: A1332</p>
    <h2>iPhone 3G <span>(Black)</span></h2><img data-src="https://cdn.example/3g.png?a=1&amp;b=2"><p>A1241</p>
    <h2>Learn more</h2><p>No image</p>`
  assert.deepEqual(imagesFromApplePage(html, models, 'https://support.apple.com/en-us/108044'), {
    'iPhone 4': 'https://support.apple.com/library/iphone4.png',
    'iPhone 3G': 'https://cdn.example/3g.png?a=1&b=2',
  })
})

test('validation blocks regressions and bad data', () => {
  const good = { id: 'iphone-4', name: 'iPhone 4', identifiers: ['iPhone3,1'], released: '2010-06-24', imageURL: 'https://x/y.png', specs: [{ title: 'Hardware', rows: [['Chip', 'A4']] }] }
  assert.deepEqual(validate([good], { models: [good] }, { 'iPhone 4': {} }), [])
  const problems = validate(
    [{ ...good, imageURL: undefined, launchPriceUSD: '199', colors: [{ name: 'Gold', hex: ['A', 'B'] }], specs: [{ title: 'Hardware', rows: [['Chip']] }] }, { ...good, identifiers: [] }],
    { models: [good, good, good] },
    { 'iPhone 5C': {} },
  )
  for (const expected of ['duplicate id iphone-4', 'iPhone 4: bad launchPriceUSD', 'iPhone 4: bad hex for Gold', 'iPhone 4: bad row in Hardware', 'iPhone 4: no identifiers', 'override "iPhone 5C" matches no model', 'model count dropped 3 → 2', 'images dropped 3 → 1'])
    assert.ok(problems.includes(expected), `missing: ${expected}\n${problems.join('\n')}`)
})
