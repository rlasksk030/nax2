/**
 * 다른 선생님께 드릴 배포판(zip) 만들기
 *   node tools/build_release.js [출력폴더]
 *
 * 만들어지는 것
 *   타자성장대회_배포판_vN/
 *     0_먼저_읽어주세요.txt
 *     설치설명서.pdf / .html
 *     학생안내문.pdf / .html
 *     코드/  (Apps Script 에 붙여넣을 파일 6개)
 *     자세한설명서.md
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const VERSION = "1.0";
const NAME = "타자성장대회_배포판_v" + VERSION;
const OUT_DIR = process.argv[2] || path.join(ROOT, "release");
const STAGE = path.join(OUT_DIR, NAME);

const CODE_FILES = [
  ["Code.gs", "1. Code.gs — 기본 Code.gs 내용을 모두 지우고 붙여넣기"],
  ["index.html", "2. index — 새 HTML 파일, 이름은 index"],
  ["style.html", "3. style — 새 HTML 파일, 이름은 style"],
  ["script.html", "4. script — 새 HTML 파일, 이름은 script"],
  ["admin.html", "5. admin — 새 HTML 파일, 이름은 admin"],
  ["adminScript.html", "6. adminScript — 새 HTML 파일, 이름은 adminScript (S가 대문자!)"]
];

function reset(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
}

function copy(from, to) {
  fs.copyFileSync(path.join(ROOT, from), path.join(STAGE, to));
}

/** 설명서를 PDF 로 만듭니다. (playwright 가 없으면 건너뜁니다) */
function makePdf(htmlPath, pdfPath) {
  const script = `
    const { chromium } = require('playwright');
    (async () => {
      const browser = await chromium.launch();
      const page = await browser.newPage();
      await page.goto('file://${htmlPath}');
      await page.waitForTimeout(1200);
      await page.emulateMedia({ media: 'print' });
      await page.pdf({ path: '${pdfPath}', format: 'A4', printBackground: true });
      await browser.close();
    })();
  `;
  execFileSync(process.execPath, ["-e", script], { stdio: "pipe" });
}

/* ---------------- 만들기 ---------------- */

reset(STAGE);
fs.mkdirSync(path.join(STAGE, "코드"));

CODE_FILES.forEach(function (item) {
  fs.copyFileSync(path.join(ROOT, item[0]), path.join(STAGE, "코드", item[0]));
});

copy("docs/설치설명서.html", "설치설명서.html");
copy("docs/학생안내문.html", "학생안내문.html");
copy("README.md", "자세한설명서.md");

fs.writeFileSync(path.join(STAGE, "0_먼저_읽어주세요.txt"),
  "⌨️ 우리 반 타자 성장대회 — 배포판 v" + VERSION + "\r\n" +
  "=".repeat(50) + "\r\n\r\n" +
  "한컴타자로 잰 기록을 학생이 입력하면,\r\n" +
  "처음보다 얼마나 자랐는지 자동으로 계산해 주는 우리 반 전용 웹앱입니다.\r\n" +
  "구글 계정만 있으면 되고, 설치비나 서버는 필요 없습니다. (약 20분)\r\n\r\n" +
  "[ 이 폴더에 무엇이 있나요 ]\r\n\r\n" +
  "  설치설명서.pdf     ← 먼저 이것부터 여세요. 순서대로 따라 하면 됩니다.\r\n" +
  "  학생안내문.pdf     ← 학생에게 나눠줄 안내문 (점수 배점 · 상 안내)\r\n" +
  "  코드/              ← Apps Script 에 붙여넣을 파일 6개\r\n" +
  "  자세한설명서.md    ← 점수 계산 방법, 시트 구조 등 자세한 내용\r\n" +
  "  (설치설명서.html, 학생안내문.html 은 브라우저로 열어보는 용도입니다)\r\n\r\n" +
  "[ 붙여넣는 순서 ]\r\n\r\n" +
  CODE_FILES.map(function (item) { return "  " + item[1]; }).join("\r\n") + "\r\n\r\n" +
  "  * HTML 파일은 이름만 넣으면 .html 이 자동으로 붙습니다.\r\n" +
  "  * 이름의 대문자·소문자가 하나라도 다르면 화면이 열리지 않습니다.\r\n\r\n" +
  "[ 붙여넣은 다음 ]\r\n\r\n" +
  "  1) Code.gs 맨 위 ADMIN_PASSWORD 를 우리 반 비밀번호로 바꾸기\r\n" +
  "  2) 편집기에서 initializeSheets 실행 → 권한 허용\r\n" +
  "  3) 학생명단 시트 B열에 우리 반 학생 이름 넣기\r\n" +
  "  4) 배포 → 새 배포 → 웹 앱 (실행: 나 / 접근: 링크가 있는 모든 사용자)\r\n" +
  "  5) 나온 주소(/exec)를 학생에게 알려주기\r\n\r\n" +
  "자세한 내용은 설치설명서.pdf 를 보세요.\r\n", "utf8");

// PDF (실패해도 배포판은 만들어집니다)
let pdfMade = 0;
[["설치설명서", "설치설명서"], ["학생안내문", "학생안내문"]].forEach(function (pair) {
  try {
    makePdf(path.join(STAGE, pair[0] + ".html"), path.join(STAGE, pair[1] + ".pdf"));
    pdfMade++;
  } catch (err) {
    console.log("  (PDF 건너뜀: " + pair[0] + " — playwright 가 없거나 실패)");
  }
});

// 압축
const zipPath = path.join(OUT_DIR, NAME + ".zip");
fs.rmSync(zipPath, { force: true });
execFileSync("zip", ["-r", "-q", zipPath, NAME], { cwd: OUT_DIR });

const size = (fs.statSync(zipPath).size / 1024).toFixed(0);
console.log("배포판 생성: " + zipPath + " (" + size + "KB, PDF " + pdfMade + "개)");
