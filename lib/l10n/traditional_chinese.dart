/// Converts the Simplified Chinese characters used by the app interface to
/// their Traditional Chinese (Taiwan) forms without a platform plugin.
///
/// Keep both strings aligned: the character at each index in [_simplified]
/// maps to the character at the same index in [_traditional].
const String _simplified =
    '审'
    '与专业东严个临为么义习书于产仅从们价优会传体余侧储关养内册写军冲准几凭击划则刚创删别办务动区协单卫厅历压参双发变叠台号后吗启员响唤园围国图场坏块坛墙声处备复头夹学实宽对导将尔尝层属岛师帮干并庆库应开异强当录径忆态总户执扫护报担拟择换据数断无旧时显暂术机权条来构标栏栗样档桥检楼横欧没浅测济浏游湾灯灵点状独环现盖码础确离积称稳竖筛签简类紧纠级纳线练细终绍经绑结给络绝统继绩绪续维综绿缀缓编缩网职联肤脚艺节范获营蓝虚补衬装裤见观规视览计认讨让训议记讲许论设访证评识词译试话询该详语误说请读课调负责败账资赛赞跃转轮软轻载较辑输边达迁过运还这进远连适选邮采释里鉴钟钥钮链销锁错键长门闭问闲间闻阅队阶际随隐韩页项顺须预领频题颜额饰馆馈验麦齐';

const String _traditional =
    '審'
    '與專業東嚴個臨為麼義習書於產僅從們價優會傳體餘側儲關養內冊寫軍衝準幾憑擊劃則剛創刪別辦務動區協單衛廳歷壓參雙發變疊臺號後嗎啟員響喚園圍國圖場壞塊壇牆聲處備復頭夾學實寬對導將爾嘗層屬島師幫幹並慶庫應開異強當錄徑憶態總戶執掃護報擔擬擇換據數斷無舊時顯暫術機權條來構標欄栗樣檔橋檢樓橫歐沒淺測濟瀏遊灣燈靈點狀獨環現蓋碼礎確離積稱穩豎篩籤簡類緊糾級納線練細終紹經綁結給絡絕統繼績緒續維綜綠綴緩編縮網職聯膚腳藝節範獲營藍虛補襯裝褲見觀規視覽計認討讓訓議記講許論設訪證評識詞譯試話詢該詳語誤說請讀課調負責敗賬資賽贊躍轉輪軟輕載較輯輸邊達遷過運還這進遠連適選郵採釋裡鑑鐘鑰鈕鏈銷鎖錯鍵長門閉問閒間聞閱隊階際隨隱韓頁項順須預領頻題顏額飾館饋驗麥齊';

String toTraditionalChinese(String source) {
  if (source.isEmpty) return source;
  final buffer = StringBuffer();
  for (final rune in source.runes) {
    final character = String.fromCharCode(rune);
    final index = _simplified.indexOf(character);
    buffer.write(
      index < 0
          ? character
          : String.fromCharCode(_traditional.codeUnitAt(index)),
    );
  }
  return buffer.toString();
}
