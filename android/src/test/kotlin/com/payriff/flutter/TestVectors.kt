package com.payriff.flutter

import java.io.File

/** Loads the shared CONTRACT vectors from the package's `test/vectors` folder. */
internal object TestVectors {
    fun load(name: String): Map<String, Any?> {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test/vectors/$name")
            if (candidate.isFile) {
                @Suppress("UNCHECKED_CAST")
                return MiniJson(candidate.readText(Charsets.UTF_8)).parse() as Map<String, Any?>
            }
            dir = dir.parentFile
        }
        throw IllegalStateException("test/vectors/$name not found above ${System.getProperty("user.dir")}")
    }
}

/** Minimal JSON reader for the vector files (org.json is a stub in local unit tests). */
internal class MiniJson(private val s: String) {
    private var i = 0

    fun parse(): Any? {
        val value = value()
        ws()
        check(i == s.length) { "trailing data at $i" }
        return value
    }

    private fun ws() {
        while (i < s.length && s[i].isWhitespace()) i++
    }

    private fun value(): Any? {
        ws()
        return when (val c = s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> str()
            't' -> literal("true", true)
            'f' -> literal("false", false)
            'n' -> literal("null", null)
            else -> if (c == '-' || c.isDigit()) num() else error("unexpected '$c' at $i")
        }
    }

    private fun literal(word: String, value: Any?): Any? {
        check(s.startsWith(word, i)) { "bad literal at $i" }
        i += word.length
        return value
    }

    private fun obj(): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        i++
        ws()
        if (s[i] == '}') { i++; return map }
        while (true) {
            ws()
            val key = str()
            ws()
            check(s[i] == ':') { "expected ':' at $i" }
            i++
            map[key] = value()
            ws()
            when (s[i++]) {
                ',' -> continue
                '}' -> return map
                else -> error("expected ',' or '}' at ${i - 1}")
            }
        }
    }

    private fun arr(): List<Any?> {
        val list = ArrayList<Any?>()
        i++
        ws()
        if (s[i] == ']') { i++; return list }
        while (true) {
            list.add(value())
            ws()
            when (s[i++]) {
                ',' -> continue
                ']' -> return list
                else -> error("expected ',' or ']' at ${i - 1}")
            }
        }
    }

    private fun str(): String {
        check(s[i] == '"') { "expected string at $i" }
        i++
        val out = StringBuilder()
        while (true) {
            val c = s[i++]
            when (c) {
                '"' -> return out.toString()
                '\\' -> when (val e = s[i++]) {
                    '"', '\\', '/' -> out.append(e)
                    'b' -> out.append('\b')
                    'f' -> out.append('\u000C')
                    'n' -> out.append('\n')
                    'r' -> out.append('\r')
                    't' -> out.append('\t')
                    'u' -> { out.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                    else -> error("bad escape at ${i - 1}")
                }
                else -> out.append(c)
            }
        }
    }

    private fun num(): Number {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
        val text = s.substring(start, i)
        return text.toLongOrNull() ?: text.toDouble()
    }
}
