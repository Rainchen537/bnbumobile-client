import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const seen = new Map();
function resolveDependency(from, name) {
  for (let current = from; ; current = path.dirname(current)) {
    const candidate = path.join(current, 'node_modules', name, 'package.json');
    if (fs.existsSync(candidate)) return path.dirname(fs.realpathSync(candidate));
    if (path.dirname(current) === current) throw new Error(`Missing dependency: ${name}`);
  }
}
function visit(directory) {
  const pkg = JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
  const key = `${pkg.name}@${pkg.version}`;
  if (seen.has(key)) return;
  const candidates = fs.readdirSync(directory).filter(name => /^(license|copying)(\.|$)/i.test(name));
  if (!candidates.length) throw new Error(`Missing license for ${key}`);
  const license = candidates.map(name => fs.readFileSync(path.join(directory, name), 'utf8')).join('\n');
  seen.set(key, license);
  for (const name of Object.keys({ ...pkg.dependencies, ...pkg.peerDependencies })) {
    try { visit(resolveDependency(directory, name)); } catch (error) {
      if (!pkg.peerDependenciesMeta?.[name]?.optional) throw error;
    }
  }
}
const project = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
for (const name of Object.keys(project.dependencies)) visit(resolveDependency(root, name));
const body = [...seen].sort(([a], [b]) => a.localeCompare(b)).map(([name, license]) => `${name}\n${'='.repeat(name.length)}\n\n${license.trim()}\n`).join('\n');
fs.writeFileSync(path.join(root, '../../assets/mail_editor/LICENSES.txt'), body);
console.log(`Bundled ${seen.size} local-editor dependency licenses.`);
