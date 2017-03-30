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
        arguments.completionFunction();
    },
    
    finalize: function(arguments) {
        // ことせかい の呼び出し
        // 怪しく cookie を渡します
        console.log(arguments);
        if ('type' in arguments) {
            type = arguments['type'];
            if (type == 'PropertyList') {
                location.href = "novelspeaker://downloadurl/" + encodeURIComponent(location.href) + ";NSC;" + document.cookie.replace(/ /g, "");
                return;
            }
            if (type == 'URL') {
                location.href = "novelspeaker://downloadurl/" + encodeURIComponent(arguments['data']);
            }
        }
        location.href = "novelspeaker://downloadurl/" + encodeURIComponent(location.href) + ";NSC;" + document.cookie.replace(/ /g, "");
    }
    
};
    
var ExtensionPreprocessingJS = new Action
