#!/usr/bin/python3
# -*- coding: utf-8 -*-

import glob
from typing import List

TEMPLATE_PATH = "topic.html"
INDEX_TEMPLATE_PATH = "index.html"

def GenerateHtml(htmlTitle, pageTitle, body, template):
    pass

class Topic:
    def __init__(self, htmlTitle:str, pageTitle:str, body:str, idnex:int) -> None:
        self.htmlTitle = htmlTitle
        self.pageTitle = pageTitle
        self.body = body
        self.index = index

def RenderHTML(template:str, topic:Topic):
    currentTemplate = template
    if topic.index > 1:
        currentTemplate = currentTemplate.replace("PREV_LINK", f'<a href="{format(topic.index - 1, "05d")}.html">前のページ</a>')
    else:
        currentTemplate = currentTemplate.replace("PREV_LINK", '')
    currentTemplate = currentTemplate.replace("NEXT_LINK", f'<a href="{format(topic.index + 1, "05d")}.html" rel="NEXT">次のページ</a>')
    return currentTemplate.replace("HTML_TITLE", topic.htmlTitle).replace("PAGE_TITLE", topic.pageTitle).replace("BODY", topic.body)

template = ""
with open(TEMPLATE_PATH, "r") as f:
    template = f.read()

indexTemplate = ""
with open(INDEX_TEMPLATE_PATH, "r") as f:
    indexTemplate = f.read()

topics = [] # type: List[Topic]
targetFiles = glob.glob("[0-9]*.txt")
targetFiles.sort()
index = 1
for file in targetFiles:
    with open(file, "r") as f:
        htmlTitle = f.readline().rstrip('\n')
        pageTitle = f.readline().rstrip('\n')
        body = f.read()
        topic = Topic(htmlTitle, pageTitle, body, index)
        topics.append(topic)
        index += 1

lis = [] # type: List[str]
for topic in topics:
    lis.append("\t<li><a href=\"" + format(topic.index, "05d") + ".html\">" + topic.pageTitle + "</a></li>")
indexHtml = indexTemplate.replace("LI_LIST", "\n".join(lis))

with open("../index.html", "w") as f:
    f.write(indexHtml)

for topic in topics:
    with open("../" + format(topic.index, "05d") + ".html", "w") as f:
        f.write(RenderHTML(template, topic))
