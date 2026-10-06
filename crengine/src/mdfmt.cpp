/***************************************************************************
 *   crengine-ng                                                           *
 *   Copyright (C) 2022,2024 Aleksey Chernov <valexlin@gmail.com>          *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or         *
 *   modify it under the terms of the GNU General Public License           *
 *   as published by the Free Software Foundation; either version 2        *
 *   of the License, or (at your option) any later version.                *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the Free Software           *
 *   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,            *
 *   MA 02110-1301, USA.                                                   *
 ***************************************************************************/

#include "mdfmt.h"

#if (USE_MD4C == 1)

#include <lvtinydom.h>

#include <string.h>

#include <md4c-html.h>

#if (USE_UTF8PROC==1)
#include <utf8proc.h>
#endif

#include <map>
#include <string>

#define TEXT_PARSER_CHUNK_SIZE 16384

bool DetectMarkdownFormat(LVStreamRef stream, const lString32& fileName) {
    // Check file extension
    lString32 nm = fileName;
    nm = nm.lowercase();
    if (!nm.endsWith(".md"))
        return false;
    // Check file size
    lvsize_t sz = stream->GetSize();
    if (sz < 5 || sz > MARKDOWN_MAX_FILE_SIZE)
        return false;
    // Checking for compliance with the text format
    LVTextParser textParser(stream, NULL, true);
    bool res = textParser.CheckFormat();
    stream->SetPos(0);
    return res;
}

typedef struct cre_md4c_parse_data_tag
{
    lString8* htmlData;
} cre_md4c_parse_data;

static void my_md4c_process_output(const MD_CHAR* chunk, MD_SIZE sz, void* userData) {
    cre_md4c_parse_data* data = (cre_md4c_parse_data*)userData;
    data->htmlData->append(chunk, sz);
}

// Whether a heading id keeps this character: a letter, a combining mark, a decimal digit or a
// connector (Unicode's "word" characters, as GitHub and GitLab keep)
static bool isSlugChar(lChar32 ch) {
#if (USE_UTF8PROC==1)
    switch (utf8proc_category(ch)) {
        case UTF8PROC_CATEGORY_LU:
        case UTF8PROC_CATEGORY_LL:
        case UTF8PROC_CATEGORY_LT:
        case UTF8PROC_CATEGORY_LM:
        case UTF8PROC_CATEGORY_LO:
        case UTF8PROC_CATEGORY_MN:
        case UTF8PROC_CATEGORY_MC:
        case UTF8PROC_CATEGORY_ME:
        case UTF8PROC_CATEGORY_ND:
        case UTF8PROC_CATEGORY_PC:
            return true;
        default:
            return false;
    }
#else
    return (lGetCharProps(ch) & (CH_PROP_ALPHA | CH_PROP_DIGIT | CH_PROP_MODIFIER)) != 0;
#endif
}

// The text of md4c's HTML: no tags, its escapes decoded
static lString8 htmlText(const lString8& html) {
    lString8 text;
    for (int i = 0; i < html.length(); i++) {
        char ch = html[i];
        if (ch == '<') {
            while (i < html.length() && html[i] != '>')
                i++;
            continue;
        }
        if (ch == '&') {
            static const char* entities[] = { "&amp;", "&", "&lt;", "<", "&gt;", ">", "&quot;", "\"" };
            bool decoded = false;
            for (int e = 0; e < 8; e += 2) {
                int len = (int)strlen(entities[e]);
                if (html.substr(i, len) == entities[e]) {
                    text << entities[e + 1];
                    i += len - 1;
                    decoded = true;
                    break;
                }
            }
            if (decoded)
                continue;
        }
        text << ch;
    }
    return text;
}

// A heading's id from its HTML (md4c's), as GitHub and GitLab make it: the text lowercased,
// keeping word characters and hyphens, each space a hyphen; written as md4c writes a link's
// target (bytes other than ASCII as %XX), so that a link to it ([text](#id)) is the same string
static lString8 headingSlug(const lString8& innerHtml) {
    static const char hex[] = "0123456789ABCDEF";
    lString32 s = Utf8ToUnicode(htmlText(innerHtml));
    lString8 slug;
    for (int i = 0; i < s.length(); i++) {
        lChar32 ch = s[i];
        if (ch == ' ') {
            slug << '-';
            continue;
        }
        if (ch != '-' && !isSlugChar(ch))
            continue;
        // Only an uppercase letter (without utf8proc, lStr_lowercase() would turn "ß" into "ÿ")
        if (lGetCharProps(ch) & CH_PROP_UPPER)
            lStr_lowercase(&ch, 1);
        lString8 bytes = UnicodeToUtf8(lString32(&ch, 1));
        for (int b = 0; b < bytes.length(); b++) {
            unsigned char c = (unsigned char)bytes[b];
            if (c < 128) {
                slug << (char)c;
            } else {
                slug << '%' << hex[c >> 4] << hex[c & 15];
            }
        }
    }
    return slug;
}

// Gives md4c's headings (<h1>...<h6>, which have no id) their GitHub ids, so that links to
// them work; a repeated id is numbered (-1, -2...), a heading with no word character gets none,
// a heading written in HTML (with attributes) keeps its own
static void addHeadingIds(lString8& html) {
    lString8 out;
    std::map<std::string, int> occurrences;
    int pos = 0;
    while (true) {
        int start = html.pos("<h", pos);
        if (start < 0 || start + 3 >= html.length())
            break;
        char level = html[start + 2];
        if (level < '1' || level > '6' || html[start + 3] != '>') {
            out.append(html.c_str() + pos, start + 2 - pos);
            pos = start + 2;
            continue;
        }
        int end = html.pos(lString8("</h") << level << '>', start + 4);
        if (end < 0)
            break;
        lString8 base = headingSlug(html.substr(start + 4, end - start - 4));
        out.append(html.c_str() + pos, start + 3 - pos);
        if (!base.empty()) {
            std::string slug = base.c_str();
            while (occurrences.count(slug)) {
                int n = ++occurrences[base.c_str()];
                slug = std::string(base.c_str()) + "-" + std::to_string(n);
            }
            occurrences[slug] = 0;
            out << " id=\"" << slug.c_str() << "\"";
        }
        pos = start + 3;
    }
    out.append(html.c_str() + pos, html.length() - pos);
    html = out;
}

bool ImportMarkdownDocument(LVStreamRef stream, const lString32& fileName, ldomDocument* doc, LVDocViewCallback* progressCallback, CacheLoadingCallback* formatCallback) {
    if (doc->openFromCache(formatCallback)) {
        if (progressCallback) {
            progressCallback->OnLoadFileEnd();
        }
        return true;
    }
    bool res = false;
    // Read stream
    lString8 rawData;
    lString8 htmlData;
    char buffer[TEXT_PARSER_CHUNK_SIZE];
    lvsize_t bytesRead = 0;
    stream->SetPos(0);
    while (stream->Read(buffer, TEXT_PARSER_CHUNK_SIZE, &bytesRead) == LVERR_OK) {
        rawData.append(buffer, bytesRead);
        if (bytesRead < TEXT_PARSER_CHUNK_SIZE)
            break;
    }
    // Parse and convert to html
    cre_md4c_parse_data parseData;
    parseData.htmlData = &htmlData;
    int parse_res = md_html(rawData.c_str(), rawData.length(), my_md4c_process_output, (void*)&parseData,
                            MD_FLAG_COLLAPSEWHITESPACE | MD_FLAG_TABLES | MD_FLAG_TASKLISTS |
                                    MD_FLAG_STRIKETHROUGH | MD_FLAG_PERMISSIVEURLAUTOLINKS |
                                    MD_FLAG_PERMISSIVEEMAILAUTOLINKS | MD_FLAG_PERMISSIVEWWWAUTOLINKS |
                                    MD_FLAG_LATEXMATHSPANS,
                            MD_HTML_FLAG_XHTML);
    rawData.clear();
    if (0 != parse_res) {
        // Parse failed
        CRLog::error("MD4C: Failed to parse Markdown document!");
        return res;
    }
    addHeadingIds(htmlData);
    // Write document content to stream to parse them
    lvsize_t result_len = htmlData.length();
    lString32 title = LVExtractFilenameWithoutExtension(fileName);
    lString8 gen_preamble = cs8(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
            "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>"
    ) + UnicodeToUtf8(title) + cs8("</title></head><body>");
    lString8 gen_tail = cs8("</body></html>");
    lvsize_t dw;
    LVStreamRef memStream = LVCreateMemoryStream();
    res = !memStream.isNull();
    if (res)
        res = LVERR_OK == memStream->Write(gen_preamble.c_str(), gen_preamble.length(), &dw);
    if (res)
        res = dw == (lvsize_t)gen_preamble.length();
    if (res) {
        res = LVERR_OK == memStream->Write(htmlData.data(), result_len, &dw);
    }
    htmlData.clear();
    if (res)
        res = dw == result_len;
    if (res)
        res = LVERR_OK == memStream->Write(gen_tail.c_str(), gen_tail.length(), &dw);
    if (res)
        res = dw == (lvsize_t)gen_tail.length();
    if (res) {
        // Parse stream to document
        ldomDocumentWriter writer(doc);
        LVHTMLParser parser(memStream, &writer);
        parser.setProgressCallback(progressCallback);
        res = parser.CheckFormat() && parser.Parse();
    }
    if (res) {
        doc->getProps()->setString(DOC_PROP_TITLE, title);
        doc->buildTocFromHeadings();
    }
    return res;
}

#endif
