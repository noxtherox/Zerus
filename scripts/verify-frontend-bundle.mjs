import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const assetsDirectory = join(process.cwd(), "dist", "assets");
const chunks = readdirSync(assetsDirectory).filter((file) => file.endsWith(".js"));
const chunkNames = new Set(chunks);
const imports = new Map();

for (const chunk of chunks) {
  const source = readFileSync(join(assetsDirectory, chunk), "utf8");
  const dependencies = [...source.matchAll(/["']\.\/([^"']+\.js)["']/g)]
    .map((match) => match[1])
    .filter((dependency) => chunkNames.has(dependency));
  imports.set(chunk, [...new Set(dependencies)]);
}

const visited = new Set();
const active = new Set();
const path = [];

function findCycle(chunk) {
  visited.add(chunk);
  active.add(chunk);
  path.push(chunk);

  for (const dependency of imports.get(chunk) ?? []) {
    if (!visited.has(dependency)) {
      const cycle = findCycle(dependency);
      if (cycle) return cycle;
      continue;
    }
    if (!active.has(dependency)) continue;

    const start = path.indexOf(dependency);
    return [...path.slice(start), dependency];
  }

  path.pop();
  active.delete(chunk);
  return null;
}

for (const chunk of chunks) {
  if (visited.has(chunk)) continue;
  const cycle = findCycle(chunk);
  if (cycle) {
    throw new Error(
      `Unsafe production chunk cycle detected: ${cycle.join(" -> ")}`,
    );
  }
}

console.log("Frontend bundle chunk graph verified.");
