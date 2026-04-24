const path = require('path')
const fs = require('fs')

const portalBaseUrl = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud'
const ideBaseUrl = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud'
const timeoutMs = Number.parseInt(process.env.PUPPETEER_TIMEOUT_MS || '45000', 10)
const e2eDir = process.env.E2E_DIR || 'tests/e2e'

const localPuppeteer = path.join(process.cwd(), e2eDir, 'node_modules', 'puppeteer')
let puppeteer
if (fs.existsSync(localPuppeteer)) {
  puppeteer = require(localPuppeteer)
} else {
  puppeteer = require('puppeteer')
}

async function probe(page, url, marker) {
  const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs })
  if (!response) {
    throw new Error(`No HTTP response for ${marker}`)
  }
  const status = response.status()
  if (status >= 500) {
    throw new Error(`${marker} returned ${status}`)
  }
}

async function main() {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] })
  try {
    const page = await browser.newPage()
    await page.setViewport({ width: 1440, height: 900 })

    await probe(page, `${portalBaseUrl}/`, 'portal-root')
    await probe(page, `${portalBaseUrl}/oauth2/sign_in`, 'portal-oauth-sign-in')
    await probe(page, `${ideBaseUrl}/`, 'ide-root')

    console.log('Puppeteer parity probe passed')
  } finally {
    await browser.close()
  }
}

main().catch((error) => {
  console.error(String(error && error.stack ? error.stack : error))
  process.exit(1)
})
