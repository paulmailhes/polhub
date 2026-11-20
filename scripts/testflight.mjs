#!/usr/bin/env node
// TestFlight pour Polhub iPhone, par l'API d'App Store Connect (20/11/2026).
//   node scripts/testflight.mjs attendre   : attend que la fiche de l'app existe (Apple interdit de la créer par l'API) ;
//   node scripts/testflight.mjs groupe     : crée le groupe interne « Paul », ouvert à toutes les versions, et y met le
//                                            titulaire du compte : chaque version envoyée arrive seule sur son iPhone.
// La clé vient de prive/appstore.env (APPSTORE_KEY_ID, APPSTORE_ISSUER_ID, APPSTORE_KEY_PATH) ; elle n'est jamais affichée.
import { readFileSync } from "node:fs";
import { createPrivateKey } from "node:crypto";

const BUNDLE = "fr.paulmailhes.polhub.ios";
const env = Object.fromEntries(readFileSync(new URL("../prive/appstore.env", import.meta.url), "utf8")
  .split("\n").filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]));

async function jeton() {
  const jwk = createPrivateKey(readFileSync(env.APPSTORE_KEY_PATH, "utf8")).export({ format: "jwk" });
  const b64u = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const tete = b64u({ alg: "ES256", kid: env.APPSTORE_KEY_ID, typ: "JWT" });
  const now = Math.floor(Date.now() / 1000);
  const corps = b64u({ iss: env.APPSTORE_ISSUER_ID, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" });
  const cle = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, cle, new TextEncoder().encode(`${tete}.${corps}`));
  return `${tete}.${corps}.${Buffer.from(sig).toString("base64url")}`;
}

async function asc(chemin, methode = "GET", corps) {
  const r = await fetch(`https://api.appstoreconnect.apple.com${chemin}`, {
    method: methode,
    headers: { authorization: `Bearer ${await jeton()}`, "content-type": "application/json" },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
  const texte = await r.text();
  return { statut: r.status, corps: texte ? JSON.parse(texte) : null };
}

async function app() {
  const r = await asc(`/v1/apps?filter[bundleId]=${BUNDLE}&fields[apps]=name,bundleId`);
  return r.corps?.data?.[0];
}

const ordre = process.argv[2];
if (ordre === "attendre") {
  for (;;) {
    const trouvee = await app();
    if (trouvee) {
      console.log(`Fiche trouvée : ${trouvee.attributes.name}`);
      process.exit(0);
    }
    await new Promise((r) => setTimeout(r, 30_000));
  }
} else if (ordre === "groupe") {
  const fiche = await app();
  if (!fiche) throw new Error("La fiche de l'app n'existe pas encore.");
  const groupes = await asc(`/v1/betaGroups?filter[app]=${fiche.id}&fields[betaGroups]=name,isInternalGroup`);
  let groupe = groupes.corps?.data?.find((g) => g.attributes.isInternalGroup);
  if (!groupe) {
    const cree = await asc("/v1/betaGroups", "POST", { data: { type: "betaGroups",
      attributes: { name: "Paul", isInternalGroup: true, hasAccessToAllBuilds: true },
      relationships: { app: { data: { type: "apps", id: fiche.id } } } } });
    if (cree.statut >= 300) throw new Error(`Groupe refusé : ${JSON.stringify(cree.corps?.errors?.map((e) => e.detail))}`);
    groupe = cree.corps.data;
  }
  // Le titulaire du compte, testeur interne : son adresse ne s'affiche pas.
  const gens = await asc("/v1/users?limit=50&fields[users]=username,roles");
  const titulaire = gens.corps?.data?.find((u) => u.attributes.roles?.includes("ACCOUNT_HOLDER")) ?? gens.corps?.data?.[0];
  if (!titulaire) throw new Error("Aucun utilisateur trouvé dans App Store Connect.");
  // Already there (a second version): nothing to add.
  const membres = await asc(`/v1/betaGroups/${groupe.id}/betaTesters?limit=200&fields[betaTesters]=email`);
  if (membres.corps?.data?.some((t) => t.attributes.email?.toLowerCase() === titulaire.attributes.username?.toLowerCase())) {
    console.log("Groupe TestFlight « Paul » prêt : chaque version arrive seule sur l'iPhone.");
    process.exit(0);
  }
  const ajout = await asc("/v1/betaTesters", "POST", { data: { type: "betaTesters",
    attributes: { email: titulaire.attributes.username },
    relationships: { betaGroups: { data: [{ type: "betaGroups", id: groupe.id }] } } } });
  const deja = ajout.corps?.errors?.some((e) => /already|existe/i.test(e.detail ?? ""));
  if (ajout.statut >= 300 && !deja) throw new Error(`Testeur refusé : ${JSON.stringify(ajout.corps?.errors?.map((e) => e.detail))}`);
  console.log("Groupe TestFlight « Paul » prêt : chaque version arrive seule sur l'iPhone.");
} else if (ordre === "pret") {
  // Attend que la dernière version envoyée soit traitée par Apple : elle est alors dans TestFlight.
  const fiche = await app();
  if (!fiche) throw new Error("La fiche de l'app n'existe pas encore.");
  // `pret 202611201131`: that build; else the last one uploaded.
  const voulue = process.argv[3];
  for (;;) {
    const filtre = voulue ? `&filter[version]=${voulue}` : "";
    const r = await asc(`/v1/builds?filter[app]=${fiche.id}${filtre}&sort=-uploadedDate&limit=1&fields[builds]=version,processingState`);
    const build = r.corps?.data?.[0];
    if (build?.attributes.processingState === "VALID") {
      console.log(`Version ${build.attributes.version} prête dans TestFlight.`);
      process.exit(0);
    }
    if (build?.attributes.processingState === "FAILED" || build?.attributes.processingState === "INVALID") {
      throw new Error(`Apple a refusé la version ${build.attributes.version} (${build.attributes.processingState}).`);
    }
    await new Promise((r) => setTimeout(r, 30_000));
  }
} else {
  console.error("Usage : node scripts/testflight.mjs attendre|groupe|pret");
  process.exit(2);
}
