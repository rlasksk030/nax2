/**
 * 배포 전 미리보기 파일 만들기
 *   node tests/build_preview.js [출력경로]
 *
 * index/style/script/admin/adminScript 를 하나의 HTML 로 합치고,
 * Google Sheets 대신 브라우저 메모리에서 도는 가짜 서버를 붙입니다.
 * (Apps Script 에 올리기 전에 화면과 흐름을 확인하는 용도입니다.)
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const OUT = process.argv[2] || path.join(__dirname, "preview.html");

function read(name) {
  return fs.readFileSync(path.join(ROOT, name), "utf8");
}

const API_NAMES = [
  "apiGetStudents", "apiGetStudentState", "apiSaveBase", "apiSaveFinal", "apiGetMyResult",
  "apiAdminLogin", "apiAdminGetData", "apiAdminRecalculate",
  "apiAdminSaveRecord", "apiAdminDeleteRecord", "apiAdminGetCsv"
];

// 가짜 Google 환경 (Node 테스트와 같은 파일을 브라우저용으로 재사용)
const fakeGoogle = read("tests/fake-google.js").replace(/module\.exports[\s\S]*$/, "");

const bootstrap = `
<script>
${fakeGoogle}
(function () {
  var sandbox = createSandbox();
  window.SpreadsheetApp = sandbox.globals.SpreadsheetApp;
  window.LockService = sandbox.globals.LockService;
  window.Utilities = { formatDate: function () {
    var d = new Date();
    function p(n) { return (n < 10 ? "0" : "") + n; }
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
           " " + p(d.getHours()) + ":" + p(d.getMinutes());
  } };
  window.Session = sandbox.globals.Session;
  window.HtmlService = sandbox.globals.HtmlService;
  window.__spreadsheet = sandbox.spreadsheet;
})();
</script>
<script>
/* ===== Code.gs 원본 ===== */
${read("Code.gs")}
</script>
<script>
/* ===== google.script.run 흉내내기 ===== */
(function () {
  var API = ${JSON.stringify(API_NAMES)};

  initializeSheets();
  // 미리보기용 샘플 기록
  apiSaveBase("김하늘", [{strokes:184,accuracy:94},{strokes:191,accuracy:96},{strokes:176,accuracy:95}]);
  apiSaveFinal("김하늘", [{strokes:240,accuracy:96},{strokes:247,accuracy:97},{strokes:252,accuracy:98}]);
  apiSaveBase("이준서", [{strokes:300,accuracy:96},{strokes:305,accuracy:97},{strokes:298,accuracy:95}]);
  apiSaveFinal("이준서", [{strokes:330,accuracy:98},{strokes:325,accuracy:98},{strokes:335,accuracy:99}]);
  apiSaveBase("박서윤", [{strokes:120,accuracy:90},{strokes:118,accuracy:89},{strokes:125,accuracy:91}]);
  apiSaveFinal("박서윤", [{strokes:210,accuracy:95},{strokes:205,accuracy:94},{strokes:215,accuracy:96}]);
  apiSaveBase("정민재", [{strokes:250,accuracy:97},{strokes:248,accuracy:96},{strokes:255,accuracy:98}]);

  function makeRunner() {
    var success = null;
    var failure = null;
    var runner = {
      withSuccessHandler: function (fn) { success = fn; return runner; },
      withFailureHandler: function (fn) { failure = fn; return runner; }
    };
    API.forEach(function (name) {
      runner[name] = function () {
        var args = Array.prototype.slice.call(arguments);
        setTimeout(function () {
          try {
            var result = window[name].apply(null, args);
            if (success) success(result);
          } catch (err) {
            if (failure) failure(err);
          }
        }, 150);
      };
    });
    return runner;
  }

  window.google = { script: {} };
  Object.defineProperty(window.google.script, "run", { get: makeRunner });
})();
</script>
`;

let html = read("index.html");
html = html.replace("<?!= include('style'); ?>", read("style.html"));
html = html.replace("<?!= include('admin'); ?>", read("admin.html"));
html = html.replace("<?!= include('script'); ?>", bootstrap + "\n" + read("script.html"));
html = html.replace("<?!= include('adminScript'); ?>", read("adminScript.html"));
html = html.replace(/<\?=\s*appTitle\s*\?>/g, "우리 반 타자 성장대회");

if (/<\?[!=]/.test(html)) {
  throw new Error("치환되지 않은 Apps Script 템플릿 태그가 남아 있습니다.");
}

fs.writeFileSync(OUT, html, "utf8");
console.log("미리보기 생성: " + OUT);
