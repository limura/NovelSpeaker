/*
 * WebSpeechViewTool で WkWebView に注入する utility script
 */

function GetPageElementArray(SiteInfo){
  if("data" in SiteInfo && "pageElement" in SiteInfo.data){
    return document.evaluate(SiteInfo.data.pageElement, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  }
  return undefined;
}

function GetNextLink(SiteInfo){
  if("data" in SiteInfo && "nextLink" in SiteInfo.data){
    return document.evaluate(SiteInfo.data.pageElement, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  }
  return undefined;
}

function isVerticalMode(element) {
    return element && element.style && element.style.writing-mode && element.style.writing-mode.indexOf("vertical") >= 0;
}

// margin はWebViewの幅や高さに対する比率(0.3とか)を指定する
function ScrollToElement(element, index, margin) {
  let range = new Range();
  range.selectNode(element);
  // 何故か //body が対象になっている時があって、その時は謎の挙動(次のTextNodeの全ての分だけスクロールするようになる)をするので index を一つずらすことで Text を選択されるようにすることで謎の挙動を回避します。
  if(index == 0 && (range.endContainer instanceof HTMLBodyElement || range.startContainer instanceof HTMLBodyElement)){
    index = 1;
  }
  if(index > 0){
    range.setStart(element, index);
    try {
      range.setEnd(element, index+1);
    }catch(e){
        console.log(`ScrollToElement() range.setEnd(element, ${index+1}) got error: ${e}`);
    }
  }
  let xMargin = window.innerWidth * margin;
  let yMargin = window.innerHeight * margin;
  rect = range.getBoundingClientRect();
  if(rect.x == 0 && rect.y == 0) { return; }
  //const isVertical = isVerticalMode(element);
  let x = window.pageXOffset + rect.left - xMargin;
  let y = window.pageYOffset + rect.top - window.innerHeight + yMargin;
  window.scrollTo({left: x, top: y, behavior: "smooth"});
  //console.log(["ScrollToElement: " + x + ", " + y + " rect: " + rect.x + ", " + rect.y, "rect.left", rect.left, "pageXOffset", window.pageXOffset, "xMargin", xMargin, `${element.textContent}`]);
}

// margin はWebViewの幅や高さに対する比率(0.3とか)を指定する
function ScrollToIndex(index, margin){
  // index がコンテンツの最大文字数以上になってると undefined を返すのが通常の動作なのだけれど、
  // 内部データ的に index が最大文字数と同じ値かそれ以上になる事があるぽい？ので
  // 怪しく 最大文字数 - 1 にまるめてしまいます(´・ω・`)
  let textLength = GenerateWholeText(elementArray, 0).length;
  if(textLength && index >= textLength) {
    index = textLength - 1;
  }
  let elementData = SearchElementFromIndex(elementArray, index);
  if(elementData){
    ScrollToElement(elementData.element, elementData.index, margin);
  }
}

// Highlight 用のspan
let highligtElement = document.createElement("canvas");
highligtElement.style.cssText = "user-select: none; background: rgba(0,255,0,0.3); z-index: 10000; position: absolute; border-radius: 3px;";
document.body.appendChild(highligtElement);

function HighlightSpeechSentence(element, text, index, length){
  //element.parentNode.scrollIntoView(true); // TEXT_NODE には scrollIntoView が無いっぽい(´・ω・`)
  let range = new Range();
  //range.selectNodeContents(element); // selectNodeContents() では子要素が無いと駄目
  range.selectNode(element);
  if(index > 0){
    range.setStart(element, index);
  }
  if(length <= 0){
    length = 1;
  }
  //console.log("range.setEnd()", element, index, index + length);
  if(text.length >= index + length) {
    range.setEnd(element, index + length);
  }else{
      console.log("text.length < index + length: " + text.length + " < " + index + " + " + length);
  }
  // selection で現在位置を表示するのが難しそうなので、現在位置を表示するための element を上に重ねる事にします。
  const rect = range.getBoundingClientRect();
  if(highligtElement){
    // getBoundingClientRect() だと、行の折返しを跨ぐ場合には「跨いでいる2行全体分」の範囲が返されるため、
    // なんとなく「1行分の高さの正方形」にする事にする。
    var w = rect.width;
    var h = rect.height;
    var left = rect.x + window.pageXOffset;
    var top = rect.y + window.pageYOffset;
    if(w > window.innerWidth / 2) {
      h = h / 2;
      w = h;
      top += h; // 横書きの場合はそのままだと上側(y軸的に少ない数字側)になってしまうので、h分 だけ下にずらす)
    }else if(h > window.innerHeight / 2){
      w = w / 2;
      h = w;
      //left += w; // 縦書きの場合はずらす先が左側(x軸的に少ない数字側)なので動かす必要はない
    }
    highligtElement.style.left = `${left}px`;
    highligtElement.style.top = `${top}px`;
    highligtElement.style.width = `${w}px`;
    highligtElement.style.height = `${h}px`;
    //console.log(`left: ${rect.x + window.pageXOffset}(${rect.x} + ${window.pageXOffset}) -> ${left}, top: ${rect.y + window.pageYOffset}(${rect.y} + ${window.pageYOffset}) -> ${top}, width: ${rect.width}, height: ${rect.height}, wh: ${w}/${h}, window: ${window.innerWidth}, ${window.innerHeight}, pageOffset: ${window.pageXOffset}, ${window.pageYOffset}`);
  }

  let selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}
function isNotSpeechElement(element){
  if(element instanceof HTMLElement){
    switch(element.tagName){
    case "SCRIPT":
    case "STYLE":
    case "NOSCRIPT":
    case "IFRAME":
    case "META":
    case "IMG":
      return true;
      break;
    default:
      break;
    }
  }
  return false;
}

function extractElement(element){
  if(isNotSpeechElement(element)){
    return [];
  }
  if(element.childNodes.length <= 0){
    var text = "";
    if(element.nodeType == Node.TEXT_NODE){
      text = element.textContent;
    }else{
      text = element.innerText;
    }
    if(!text /*|| text.trim().length <= 0*/){
      return [];
    }
    return [{"element": element, "text": text}];
  }
  var elementArray = [];
  for(var i = 0; i < element.childNodes.length; i++){
    let childNode = element.childNodes[i];
    elementArray = elementArray.concat(extractElement(childNode))
  }
  return elementArray;
}

function HideOtherElements(rootElement, elementArray) {
    for(var i = 0; i < elementArray.length; i++) {
        const element = elementArray[i].element;
        if(rootElement === element){
            return true;
        }
    }
    
    var hit = false;
    for(var i = 0; i < rootElement.childNodes.length; i++) {
        const childNode = rootElement.childNodes[i];
        const result = HideOtherElements(childNode, elementArray);
        if(result){ hit = true; }
    }
    if(hit){ return true; }
    if(rootElement.style) {
        if(rootElement.style.cssText) {
            rootElement.style.cssText += "display: none !important;";
        }else{
            rootElement.style.cssText += "display: none !important;";
        }
    }
    return false
}

function extractElementForPageElementArray(pageElementArray){
  var elementArray = [];
  for(var i = 0; i < pageElementArray.snapshotLength; i++){
    let element = pageElementArray.snapshotItem(i);
    elementArray = elementArray.concat(extractElement(element));
  }
  return elementArray;
}

// [{"element":, "text":}, ...] の配列の text の文字を index として、
// index (0 起点) で示される element の何文字目であるかを返す({"element":, "text":, "index":})
// 見つからなければ undefined が返ります
function SearchElementFromIndex(elementArray, index){
  var i = 0;
  for(var i = 0; i < elementArray.length && index >= 0; i++){
    let data = elementArray[i];
    let element = data["element"];
    let text = data["text"];
    let textLength = text.length;
    if(index < textLength){
      return {"element": element, "text": text, "index": index}
    }
    index -= textLength;
  }
  return undefined
}

function isElementInRange(element, range) {
    let elementRange = new Range();
    elementRange.selectNode(element);
    // elementRange の開始点と終了点を es, ee
    // range の開始点と終了点を rs, re
    // とした場合、範囲外なのは ee < rs, re < es であるのでそう比較する
    // 参考: https://lab.syncer.jp/Web/API_Interface/Reference/IDL/Range/compareBoundaryPoints/
    if(elementRange.compareBoundaryPoints(Range.END_TO_START, range) > 0 ||
       elementRange.compareBoundaryPoints(Range.START_TO_END, range) < 0) { return false; }
    return true;
}

// elementArray から range で示された範囲を検索する。
// 返り値としては、
/*
 {
    elementArray: [element],
    prevElementArray: [element],
    afterElementArray: [element],
    startIndex: int,
    endIndex: int,
 }
 */
// となる。
// element は与えられた elementArray の一要素と同じで、
// startIndex は、range の先頭位置が、与えられた elementArray の最初の文字からの何文字目に当たるかの数
// endIndex は、range の末尾が、与えられた elementArray の最初の文字からの何文字目に当たるかの数
// であり、発見できなかったり何らかの問題があった場合は undefined が返る。
function SplitElementFromSelection(elementArray, range){
    var resultArray = [];
    var prevArray = [];
    var afterArray = [];
    var isHit = false;
    var index = 0;
    var startIndex = 0;
    var endIndex = 0;
    for(var i = 0; i < elementArray.length; i++){
        let data = elementArray[i];
        let element = data["element"];
        let text = data["text"];
      
        let elementRange = new Range();
        elementRange.selectNode(element);
        
        // element が範囲外である場合
        if(elementRange.compareBoundaryPoints(Range.END_TO_START, range) > 0 ||
            elementRange.compareBoundaryPoints(Range.START_TO_END, range) < 0){
            if(isHit){
                afterArray.push(data);
            }else{
                index += text.length;
                prevArray.push(data);
            }
            continue;
        }
        // ここに来るのは範囲内の場合なのでもう少し詳しく確認する
        if(isHit == false /*elementRange.compareBoundaryPoints(Range.START_TO_START, range) < 0*/){
            // 範囲内になった最初のelement
            isHit = true;
            if(range.startContainer === element) {
                /// range.startOffset が range で指定された element なら startOffset を信用して良い
                startIndex = index + range.startOffset;
            }else{
                startIndex = index;
            }
        }
        if(endIndex == 0 && elementRange.compareBoundaryPoints(Range.END_TO_END, range) >= 0){
            // 範囲内になる最後のelment
            if(range.endContainer === element) {
                endIndex = index + range.endOffset;
            }else{
                endIndex = index + text.length;
            }
        }
        index += text.length;
        resultArray.push(data);
    }
    if(resultArray.length <= 0){
        return undefined;
    }
    //console.log({elementArray: resultArray.length, startIndex: startIndex, endIndex: endIndex, prevElementArray: prevArray.length, afterElementArray: afterArray.length});
    return {elementArray: resultArray, startIndex: startIndex, endIndex: endIndex, prevElementArray: prevArray, afterElementArray: afterArray};
}

// [{"element":, "text":}, ...] の配列の text の文字を、全部組み合わせた文字列を取得します
// index は最初のelementでのオフセットになります
function GenerateWholeText(elementArray, index){
  var text = "";
  elementArray.forEach(function(data){
    if(data["text"].length >= index){
      text += data["text"].slice(index);
      index = 0;
    }else{
      index -= data["text"].length;
    }
  });
  return text;
}
function SelectionRangeToIndex(range){
    let speechTarget = SplitElementFromSelection(elementArray, range);
    if(speechTarget){
        return { startIndex: speechTarget.startIndex, endIndex: speechTarget.endIndex };
    }
    return undefined;
}
function GetSelectedIndex(){
  let selection = window.getSelection();
  var index = -1;
  if(selection.rangeCount > 0){
    let result = SelectionRangeToIndex(selection.getRangeAt(0));
    return result.startIndex;
  }else{
    index = 0;
  }
  return index;
}
function GetSelectedRange(){
  let selection = window.getSelection();
  var index = -1;
  var length = -1;
  if(selection.rangeCount > 0){
    return SelectionRangeToIndex(selection.getRangeAt(0));
  }
  return null;
}
function GetSelectedString(){
    const selection = window.getSelection();
    if(selection){
        return selection.toString();
    }
    return undefined;
}

function HighlightFromIndex(index, length){
    // index がコンテンツの最大文字数以上になってると undefined を返すのが通常の動作なのだけれど、
    // 内部データ的に index が最大文字数と同じ値かそれ以上になる事があるぽい？ので
    // 怪しく 最大文字数 - 1 にまるめてしまいます(´・ω・`)
    let textLength = GenerateWholeText(elementArray, 0).length;
    if(textLength && index >= textLength) {
      index = textLength - 1;
    }
    let elementData = SearchElementFromIndex(elementArray, index);
    if(elementData){
      HighlightSpeechSentence(elementData.element, elementData.text, elementData.index, length);
    }
}

function EnableSelection(){
  let input = document.getElementById("focusInput");
  input.selectionStart = 0;
  input.selectionEnd = 1;
  //document.getElementById("focusInput").focus();
  if(elementArray.length >= 1) {
    let element = elementArray[0].element;
    let range = document.createRange();
    range.selectNode(element);
    let selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    return "OK";
  }
  return "NG";
}

function CreateElementArray(SiteInfoArray){
    if(SiteInfoArray === undefined) {
        SiteInfoArray = [{"data":{url:".*", pageElement:"//body", title:"//title", nextLink:"", author:"", firstPageLink:"", tag:""}}];
    }
    //console.log("CreateElementArray with SiteInfo: " + JSON.stringify(SiteInfoArray));
    for(let i = 0; i < SiteInfoArray.length; i++){
        let siteInfo = SiteInfoArray[i];
        let pageElementArray = GetPageElementArray(siteInfo);
        if(pageElementArray){
            return extractElementForPageElementArray(pageElementArray);
        }
    }
    return undefined;
}

function GetCurrentDisplayLocation(xRatio, yRatio) {
    const x = window.innerWidth * xRatio;
    const y = window.innerHeight * yRatio;
    const range = document.caretRangeFromPoint(x, y);
    if(range) {
        const indexDic = SelectionRangeToIndex(range);
        if("startIndex" in indexDic) {
            return indexDic.startIndex;
        }
    }
    return undefined;
}

var elementArray = CreateElementArray();
"OK";
