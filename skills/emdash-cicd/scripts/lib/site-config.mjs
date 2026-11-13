#!/usr/bin/env node
// site-config.mjs — leitura e ajuste dos arquivos de configuração de um site EmDash.
// Usado por init-site.sh, provision.sh e pipeline.sh para que nenhum deles edite
// wrangler.jsonc / astro.config.mjs "na mão".
//
// Só mexe em linhas que o template starter-cloudflare do EmDash já traz: nomes de
// recursos, o database_id e a ativação do sandbox. Não cria binding nem recurso novo.
//
// Uso:
//   site-config.mjs get <campo>                      campo: name | database_name | database_id | bucket_name
//   site-config.mjs set-names <worker> [<bucket>]    nomes do Worker/D1 (= worker) e do R2
//   site-config.mjs set-database-id <uuid>           fixa o UUID do D1 no binding DB
//   site-config.mjs enable-sandbox                   LOADER no wrangler.jsonc + sandboxRunner no astro.config.mjs
//   site-config.mjs ignore-evidence                  backups/ e lock no .gitignore
//   site-config.mjs resolve-upstream <emdash> <tpl>  package.json do template com versões publicadas (stdout)
//   site-config.mjs workspace-yaml                   pnpm-workspace.yaml padrão dos templates cloudflare (stdout)
// Exit: 0 ok; 1 falha; 2 uso.
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const WRANGLER = "wrangler.jsonc";
const ASTRO = "astro.config.mjs";

const fail = (msg, code = 1) => {
	console.error(`FAIL  ${msg}`);
	process.exit(code);
};
const read = (f) => (existsSync(f) ? readFileSync(f, "utf8") : fail(`${f} não encontrado`));
const stripComments = (s) => s.replace(/^\s*\/\/.*$/gm, "");

function get(field) {
	const text = stripComments(read(WRANGLER));
	const m = text.match(new RegExp(`"${field}"\\s*:\\s*"([^"]*)"`));
	process.stdout.write(m ? m[1] : "");
}

function setValue(text, key, value) {
	const re = new RegExp(`^(\\s*"${key}"\\s*:\\s*")[^"]*(")`, "m");
	if (!re.test(text)) fail(`chave "${key}" não encontrada em ${WRANGLER}`);
	return text.replace(re, `$1${value}$2`);
}

function setNames(worker, bucket = `${worker}-media`) {
	if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(worker)) fail(`nome inválido: ${worker} (minúsculas, dígitos e hífen)`, 2);
	let text = read(WRANGLER);
	text = setValue(text, "name", worker);
	text = setValue(text, "database_name", worker);
	text = setValue(text, "bucket_name", bucket);
	writeFileSync(WRANGLER, text);
	console.log(`PASS  nomes: Worker e D1 "${worker}", R2 "${bucket}"`);
}

function setDatabaseId(uuid) {
	if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(uuid)) fail(`UUID inválido: ${uuid}`, 2);
	let text = read(WRANGLER);
	const current = stripComments(text).match(/"database_id"\s*:\s*"([^"]*)"/)?.[1];
	if (current === uuid) return console.log(`PASS  database_id já fixado (${uuid})`);
	if (current) fail(`${WRANGLER} já aponta para outro banco (${current}); não sobrescrevo — conferir à mão`);
	const re = /^(\s*)("database_name"\s*:\s*"[^"]*",?)\s*$/m;
	if (!re.test(text)) fail(`"database_name" não encontrado em ${WRANGLER}`);
	text = text.replace(re, (_all, indent, line) => {
		const withComma = line.endsWith(",") ? line : `${line},`;
		return `${indent}${withComma}\n${indent}"database_id": "${uuid}",`;
	});
	writeFileSync(WRANGLER, text);
	console.log(`PASS  database_id fixado em ${WRANGLER} (${uuid})`);
}

// Mesmo efeito do scaffolder com --sandboxed-plugins (que descomenta worker_loaders),
// mais o sandboxRunner que a doc deployment/plugin-sandbox.mdx pede no passo 3.
function enableSandbox() {
	let w = read(WRANGLER);
	if (/^\s*"worker_loaders"\s*:/m.test(w)) {
		console.log("PASS  worker_loaders já ativo");
	} else if (/^\s*\/\/\s*"worker_loaders"\s*:/m.test(w)) {
		w = w.replace(/^(\s*)\/\/\s*("worker_loaders"\s*:.*)$/m, "$1$2");
		w = w.replace(/(Worker Loader, available on Workers paid plans\.) Uncomment to enable:/, "$1");
		writeFileSync(WRANGLER, w);
		console.log("PASS  worker_loaders LOADER descomentado");
	} else {
		fail(`linha worker_loaders não encontrada em ${WRANGLER} — acrescentar conforme deployment/plugin-sandbox.mdx`);
	}

	let a = read(ASTRO);
	if (/sandboxRunner\s*:/.test(a)) return console.log("PASS  sandboxRunner já configurado");
	const importRe = /import\s*\{([^}]*)\}\s*from\s*"@emdash-cms\/cloudflare";/;
	const storageRe = /^(\s*)(storage\s*:\s*r2\([^)]*\)\s*,?)\s*$/m;
	if (!importRe.test(a) || !storageRe.test(a)) {
		fail(`${ASTRO} não tem a forma do template — acrescentar "sandboxRunner: sandbox()" à mão`);
	}
	a = a.replace(importRe, (_all, names) => {
		const list = names.split(",").map((n) => n.trim()).filter(Boolean);
		if (!list.includes("sandbox")) list.push("sandbox");
		return `import { ${list.join(", ")} } from "@emdash-cms/cloudflare";`;
	});
	a = a.replace(storageRe, (_all, indent, line) => {
		const withComma = line.endsWith(",") ? line : `${line},`;
		return `${indent}${withComma}\n${indent}sandboxRunner: sandbox(),`;
	});
	writeFileSync(ASTRO, a);
	console.log("PASS  sandboxRunner: sandbox() acrescentado ao astro.config.mjs");
}

function ignoreEvidence() {
	const file = ".gitignore";
	const current = existsSync(file) ? readFileSync(file, "utf8") : "";
	const lines = current.split(/\r?\n/).map((l) => l.trim());
	const missing = ["backups/", ".emdash-cicd-deploy.lock"].filter((l) => !lines.includes(l));
	if (missing.length === 0) return console.log("PASS  .gitignore já cobre as evidências do pipeline");
	const block = `\n# Evidências locais do pipeline emdash-cicd (não são código do site)\n${missing.join("\n")}\n`;
	writeFileSync(file, current.replace(/\n*$/, "\n") + block);
	console.log(`PASS  .gitignore: ${missing.join(", ")}`);
}

// Reproduz scripts/sync-templates-repo.mjs do EmDash: troca "catalog:" e "workspace:*"
// pelas versões publicadas. É o que o repositório público de templates recebe.
function resolveUpstream(root, template) {
	const yaml = read(join(root, "pnpm-workspace.yaml"));
	const catalog = {};
	let inCatalog = false;
	for (const line of yaml.split("\n")) {
		if (line.startsWith("catalog:")) {
			inCatalog = true;
			continue;
		}
		if (inCatalog && /^\S/.test(line)) break;
		const m = inCatalog && line.match(/^\s+"?([^"]+)"?:\s+(.+)$/);
		if (m) catalog[m[1]] = m[2].trim();
	}
	const workspace = {};
	for (const base of [join(root, "packages"), join(root, "packages/plugins")]) {
		if (!existsSync(base)) continue;
		for (const entry of readdirSync(base, { withFileTypes: true })) {
			const p = join(base, entry.name, "package.json");
			if (!entry.isDirectory() || !existsSync(p)) continue;
			const pkg = JSON.parse(readFileSync(p, "utf8"));
			if (pkg.name && pkg.version) workspace[pkg.name] = pkg.version;
		}
	}
	const resolve = (deps = {}) =>
		Object.fromEntries(
			Object.entries(deps).map(([name, v]) => {
				if (v === "catalog:") return [name, catalog[name] ?? fail(`sem versão no catálogo para ${name}`)];
				if (v.startsWith("workspace:")) return [name, workspace[name] ? `^${workspace[name]}` : fail(`pacote ${name} não encontrado no upstream`)];
				return [name, v];
			}),
		);
	const pkg = JSON.parse(read(join(root, "templates", template, "package.json")));
	pkg.packageManager = JSON.parse(read(join(root, "package.json"))).packageManager;
	pkg.dependencies = resolve(pkg.dependencies);
	pkg.devDependencies = resolve(pkg.devDependencies);
	process.stdout.write(`${JSON.stringify(pkg, null, 2)}\n`);
}

const WORKSPACE_YAML = `# Build scripts: allow only what each runtime needs; rest false so
# strictDepBuilds (pnpm >=10.26 / 11) passes.
allowBuilds:
  esbuild: true
  workerd: true
  sharp: false

# Supply-chain hardening: cooldown on brand-new releases (EmDash exempt)
# and no non-registry transitive sources. (No trustPolicy: no-downgrade --
# it trips on upstream provenance regressions we don't control.)
minimumReleaseAge: 1440
minimumReleaseAgeExclude:
  - emdash
  - "@emdash-cms/*"
blockExoticSubdeps: true
`;

const [cmd, ...args] = process.argv.slice(2);
switch (cmd) {
	case "get":
		get(args[0]);
		break;
	case "set-names":
		args[0] ? setNames(args[0], args[1]) : fail("uso: set-names <worker> [<bucket>]", 2);
		break;
	case "set-database-id":
		args[0] ? setDatabaseId(args[0]) : fail("uso: set-database-id <uuid>", 2);
		break;
	case "enable-sandbox":
		enableSandbox();
		break;
	case "ignore-evidence":
		ignoreEvidence();
		break;
	case "resolve-upstream":
		args.length === 2 ? resolveUpstream(args[0], args[1]) : fail("uso: resolve-upstream <emdash> <template>", 2);
		break;
	case "workspace-yaml":
		process.stdout.write(WORKSPACE_YAML);
		break;
	default:
		fail("uso: site-config.mjs get|set-names|set-database-id|enable-sandbox|ignore-evidence|resolve-upstream|workspace-yaml", 2);
}
