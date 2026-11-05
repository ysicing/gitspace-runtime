const fs = require('node:fs')
const path = require('node:path')
const { createRequire } = require('node:module')

const [codeServer, home, port] = process.argv.slice(2)
const yaml = createRequire(fs.realpathSync(codeServer))('js-yaml')
const directory = path.join(home, '.config/code-server')
const configPath = path.join(directory, 'config.yaml')
const runtimePath = path.join(directory, '.gitspace-runtime.yaml')

try {
  const defaults = { 'bind-addr': `0.0.0.0:${port}`, auth: 'password', cert: false }
  if (!fs.existsSync(configPath)) {
    fs.writeFileSync(configPath, yaml.dump(defaults), { mode: 0o600, flag: 'wx' })
  }
  const config = yaml.load(fs.readFileSync(configPath, 'utf8')) ?? {}
  if (typeof config !== 'object' || Array.isArray(config)) {
    throw new Error('Expected a YAML mapping')
  }
  const runtime = {
    ...config,
    ...defaults,
    'user-data-dir': path.join(home, '.local/share/code-server'),
    'extensions-dir': path.join(home, '.local/share/code-server/extensions')
  }
  for (const key of ['password', 'hashed-password', 'host', 'port', 'socket', 'socket-mode', 'cert-key']) {
    delete runtime[key]
  }
  const temporary = fs.mkdtempSync(path.join(directory, '.gitspace-config-'))
  try {
    const staged = path.join(temporary, 'config.yaml')
    fs.writeFileSync(staged, yaml.dump(runtime), { mode: 0o600, flag: 'wx' })
    fs.renameSync(staged, runtimePath)
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true })
  }
} catch {
  console.error('Unable to prepare code-server configuration; check config.yaml and directory permissions')
  process.exitCode = 1
}
