// 프론트 기본 검사 - 코드를 고친 뒤, 커밋 전에 실행: npm test
// 1) index.html 안의 스크립트에 문법 오류가 없는지
// 2) www/index.html 이 index.html 과 같은지 (npm run build 를 빠뜨리지 않았는지)
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
let failed = 0;

const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let m, count = 0;
while ((m = re.exec(html))) {
  count++;
  try {
    new Function(m[1]);
  } catch (e) {
    failed++;
    console.log(`[실패] index.html 스크립트 ${count}번: ${e.message}`);
  }
}
if (count === 0) {
  failed++;
  console.log('[실패] index.html 에서 스크립트를 찾지 못했어요.');
}

const wwwPath = path.join(root, 'www/index.html');
if (!fs.existsSync(wwwPath) || fs.readFileSync(wwwPath, 'utf8') !== html) {
  failed++;
  console.log('[실패] www/index.html 이 index.html 과 달라요. npm run build 를 먼저 실행하세요.');
}

if (failed) {
  console.log(`검사 실패 ${failed}건`);
  process.exit(1);
}
console.log(`검사 통과 (스크립트 ${count}개 문법, www 빌드 최신)`);
