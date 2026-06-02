// Test the RunPod worker-comfyui endpoint: face swap (ReActor) + bg removal (RMBG).
// Usage: node test_runpod.mjs <endpoint_id> <runpod_key> <target.png> <source.jpg>
import { readFileSync, writeFileSync } from 'fs';

const [EP, KEY, TARGET, SOURCE] = process.argv.slice(2);
const b64 = (p) => readFileSync(p).toString('base64');

const workflow = {
  "1": { class_type: "LoadImage", inputs: { image: "target.png" }, _meta: { title: "target" } },
  "2": { class_type: "LoadImage", inputs: { image: "source.png" }, _meta: { title: "source" } },
  "3": {
    class_type: "ReActorFaceSwap",
    inputs: {
      enabled: true,
      input_image: ["1", 0],
      source_image: ["2", 0],
      swap_model: "inswapper_128.onnx",
      facedetection: "retinaface_resnet50",
      face_restore_model: "GFPGANv1.4.pth",
      face_restore_visibility: 1,
      codeformer_weight: 1,
      detect_gender_input: "no",
      detect_gender_source: "no",
      input_faces_index: "0",
      source_faces_index: "0",
      console_log_level: 1,
    },
    _meta: { title: "ReActor" },
  },
  "4": {
    class_type: "RMBG",
    inputs: { image: ["3", 0], model: "RMBG-2.0", sensitivity: 1.0, process_res: 1024, mask_blur: 2, mask_offset: 0, invert_output: false, refine_foreground: false, background: "Alpha" },
    _meta: { title: "RMBG" },
  },
  "5": { class_type: "SaveImage", inputs: { images: ["4", 0], filename_prefix: "bgr_fswap" }, _meta: { title: "save" } },
};

const body = { input: { workflow, images: [
  { name: "target.png", image: b64(TARGET) },
  { name: "source.png", image: b64(SOURCE) },
] } };

const t0 = Date.now();
const el = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
console.log(`[${el()}] POST /runsync ...`);
const r = await fetch(`https://api.runpod.ai/v2/${EP}/runsync`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${KEY}` },
  body: JSON.stringify(body),
});
const j = await r.json();
console.log(`[${el()}] status=${j.status} delayMs=${j.delayTime} execMs=${j.executionTime}`);

// worker-comfyui returns images under output.images[] (base64 or url)
const out = j.output;
if (j.error || (out && out.error)) { console.log("ERROR:", JSON.stringify(j.error || out.error).slice(0, 600)); }
const imgs = out?.images || out?.message || [];
if (Array.isArray(imgs) && imgs.length) {
  const first = imgs[0];
  const data = first.data || first.image || first;
  if (typeof data === "string" && data.length > 100) {
    writeFileSync("runpod_out.png", Buffer.from(data.replace(/^data:.*,/, ""), "base64"));
    console.log(`[${el()}] saved runpod_out.png (${(Buffer.from(data, "base64").length/1024).toFixed(0)}KB)`);
  } else { console.log("image entry:", JSON.stringify(first).slice(0, 300)); }
} else {
  console.log("raw output (first 800 chars):", JSON.stringify(out).slice(0, 800));
}
