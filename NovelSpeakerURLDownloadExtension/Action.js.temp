//
//  Action.js
//  NovelSpeakerURLDownloadExtension
//
//  Created by 飯村卓司 on 2016/09/27.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

var Action = function() {};

Action.prototype = {
    
    run: function(arguments) {
        //document.body.style.backgroundColor = "red";

        arguments.completionFunction({
             "cookie": document.cookie,
             "url": location.href,
             "html": document.getElementsByTagName("html")[0].innerHTML
        });
    },
    
    finalize: function(arguments) {
        // ことせかい の呼び出し
        // 怪しく cookie を渡します
        console.log(arguments);
        targetUrl = location.href;
        targetCookie = document.cookie;
        if ('type' in arguments) {
            type = arguments['type'];
            if (type == 'URL') {
                targetUrl = arguments['data'];
                targetCookie = "";
            }
        }
        //document.body.style.backgroundColor = "blue";

        // cookie は # の後ろに encodeURIComponent() した状態で渡すことにします。
        // したがって元のURLからは # 以下の fragment を消します。
        location.href = "novelspeaker://downloadurl/" + encodeURIComponent(targetUrl.replace(/#.*$/, "")) + "#" + encodeURIComponent(targetCookie);
    }
    
};
    
var ExtensionPreprocessingJS = new Action
