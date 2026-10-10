// Secure, read-only archive of exactly the migrated roots and nested collection groups.
// ZIP uses STORE (no compression), with standard CRC32 and a SHA-256 manifest.
// Never import helpers/firebase: legacy helper contains unrelated embedded credentials.
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { DocumentReference, FieldPath, GeoPoint, Timestamp, getFirestore } from "firebase-admin/firestore";
import { createHash } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, stat, unlink, writeFile } from "node:fs/promises";
import { once } from "node:events";
import { join, resolve } from "node:path";

process.umask(0o077);
const outputIndex = process.argv.indexOf("--output");
if (outputIndex < 0 || !process.argv[outputIndex + 1]) throw new Error("--output <secure-directory> required");
const output = resolve(process.argv[outputIndex + 1]);
const names = ["users","services","bookings","activities","apiKeys","device_tokens","googlePlacesCache","opportunities","reviews"];
const selectedIndex = process.argv.indexOf("--collections");
const selected = selectedIndex < 0 ? names : process.argv[selectedIndex + 1].split(",");
if (selected.some(x => !names.includes(x))) throw new Error("unknown migrated collection");
const db = getFirestore(initializeApp({ credential: applicationDefault() }));
function encode(value: unknown): unknown {
  if (value instanceof Timestamp) return { $type:"timestamp", seconds:value.seconds, nanoseconds:value.nanoseconds };
  if (value instanceof DocumentReference) return { $type:"reference", path:value.path };
  if (value instanceof GeoPoint) return { $type:"geopoint", latitude:value.latitude, longitude:value.longitude };
  if (Buffer.isBuffer(value)) return { $type:"bytes", base64:value.toString("base64") };
  if (value instanceof Date) return { $type:"date", iso:value.toISOString() };
  if (typeof value === "number" && !Number.isFinite(value)) return { $type:"number", value:String(value) };
  if (Array.isArray(value)) return value.map(encode);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,encode(v)]));
  return value;
}
const crcTable = Array.from({length:256},(_,n) => {
  for (let k=0;k<8;k++) n=(n&1)?0xedb88320^(n>>>1):n>>>1;
  return n>>>0;
});
async function writeZip(path: string, files: string[]) {
  const stream = createWriteStream(path,{flags:"wx",mode:0o600});
  const central: Buffer[] = [];
  let offset=0;
  async function append(bytes: Buffer) { if (!stream.write(bytes)) await once(stream,"drain"); offset+=bytes.length; }
  for (const file of files) {
    const name=Buffer.from(file.split("/").pop()!);
    const start=offset;
    const header=Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50,0); header.writeUInt16LE(20,4); header.writeUInt16LE(8,6);
    header.writeUInt16LE(name.length,26);
    await append(header); await append(name);
    let crc=0xffffffff, size=0;
    for await (const chunk of createReadStream(file)) {
      const bytes=chunk as Buffer;
      for (const byte of bytes) crc=crcTable[(crc^byte)&255]^(crc>>>8);
      size+=bytes.length;
      if (size>0xffffffff) throw new Error("ZIP64 required; refusing oversized archive");
      await append(bytes);
    }
    crc=(crc^0xffffffff)>>>0;
    const descriptor=Buffer.alloc(16);
    descriptor.writeUInt32LE(0x08074b50,0); descriptor.writeUInt32LE(crc,4);
    descriptor.writeUInt32LE(size,8); descriptor.writeUInt32LE(size,12);
    await append(descriptor);
    const entry=Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50,0); entry.writeUInt16LE(20,4); entry.writeUInt16LE(20,6);
    entry.writeUInt16LE(8,8); entry.writeUInt32LE(crc,16); entry.writeUInt32LE(size,20);
    entry.writeUInt32LE(size,24); entry.writeUInt16LE(name.length,28); entry.writeUInt32LE(start,42);
    central.push(Buffer.concat([entry,name]));
  }
  const start=offset;
  for (const entry of central) await append(entry);
  const end=Buffer.alloc(22); end.writeUInt32LE(0x06054b50,0);
  end.writeUInt16LE(files.length,8); end.writeUInt16LE(files.length,10);
  end.writeUInt32LE(offset-start,12); end.writeUInt32LE(start,16);
  await append(end); stream.end(); await once(stream,"finish");
}
async function main() {
  await mkdir(output,{recursive:true,mode:0o700});
  for (const name of selected) {
    const zipPath=join(output,name+".zip");
    try { await stat(zipPath); throw new Error(name+" archive already exists; use a new snapshot directory"); }
    catch (error) { if ((error as NodeJS.ErrnoException).code!=="ENOENT") throw error; }
    const path=join(output,name+".ndjson");
    const stream=createWriteStream(path,{flags:"wx",mode:0o600});
    const hash=createHash("sha256");
    const counts: Record<string,number> = {};
    const startedAt=new Date().toISOString();
    const sources = [db.collection(name)];
    if (name==="users" || name==="device_tokens") sources.push(db.collectionGroup("tokens") as any);
    if (name==="services") sources.push(db.collectionGroup("userServices") as any);
    if (name==="opportunities") sources.push(db.collectionGroup("interestedUsers") as any);
    if (name==="reviews") sources.push(db.collectionGroup("performerReviews") as any,db.collectionGroup("bookerReviews") as any);
    let total=0;
    for (const source of sources) {
      let cursor;
      while (true) {
        let query=source.orderBy(FieldPath.documentId()).limit(500);
        if (cursor) query=query.startAfter(cursor);
        const page=await query.get();
        if (page.empty) break;
        for (const doc of page.docs) {
          if (doc.ref.path.split("/")[0]!==name) continue;
          const line=JSON.stringify({path:doc.ref.path,createTime:encode(doc.createTime),updateTime:encode(doc.updateTime),data:encode(doc.data())})+"\n";
          hash.update(line);
          if (!stream.write(line)) await once(stream,"drain");
          const group=doc.ref.parent.id; counts[group]=(counts[group]??0)+1; total++;
        }
        cursor=page.docs[page.docs.length-1];
        if (page.size<500) break;
      }
    }
    stream.end(); await once(stream,"finish");
    const manifestPath=join(output,name+".manifest.json");
    await writeFile(manifestPath,JSON.stringify({format:"tapped-firestore-archive-v1",projectId:process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? "in-the-loop-306520",collection:name,
      startedAt,finishedAt:new Date().toISOString(),counts,total,
      note:"Only migrated roots and nested groups are included. Nanosecond timestamps, reference paths, bytes and geopoints are tagged losslessly.",
      files:{[name+".ndjson"]:{sha256:hash.digest("hex"),bytes:(await stat(path)).size}}},null,2),{mode:0o600,flag:"wx"});
    await writeZip(zipPath,[path,manifestPath]);
    const zipHash=createHash("sha256");
    for await(const chunk of createReadStream(zipPath)) zipHash.update(chunk);
    await writeFile(zipPath+".sha256",zipHash.digest("hex")+"  "+name+".zip\n",{mode:0o600,flag:"wx"});
    await unlink(path); await unlink(manifestPath);
    console.log(JSON.stringify({collection:name,total,counts,archive:zipPath}));
  }
}
main().catch(error => { console.error(error instanceof Error ? error.message : "archive failed"); process.exitCode=1; });
