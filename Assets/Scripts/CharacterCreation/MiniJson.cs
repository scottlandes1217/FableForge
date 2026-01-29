using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public static class MiniJson
{
    public static object Deserialize(string json)
    {
        if (string.IsNullOrEmpty(json))
        {
            return null;
        }

        return Parser.Parse(json);
    }

    public static string Serialize(object obj)
    {
        return Serializer.Serialize(obj);
    }

    private sealed class Parser : IDisposable
    {
        private const string WordBreak = "{}[],:\"";

        private readonly StringReader reader;

        private Parser(string json)
        {
            reader = new StringReader(json);
        }

        public static object Parse(string json)
        {
            using (var instance = new Parser(json))
            {
                return instance.ParseValue();
            }
        }

        public void Dispose()
        {
            reader.Dispose();
        }

        private Dictionary<string, object> ParseObject()
        {
            var table = new Dictionary<string, object>();

            reader.Read();

            while (true)
            {
                switch (NextToken)
                {
                    case Token.None:
                        return null;
                    case Token.CurlyClose:
                        return table;
                    default:
                        var name = ParseString();
                        if (name == null)
                        {
                            return null;
                        }

                        if (NextToken != Token.Colon)
                        {
                            return null;
                        }

                        reader.Read();

                        table[name] = ParseValue();
                        break;
                }
            }
        }

        private List<object> ParseArray()
        {
            var array = new List<object>();

            reader.Read();

            var parsing = true;
            while (parsing)
            {
                var token = NextToken;
                switch (token)
                {
                    case Token.None:
                        return null;
                    case Token.SquareClose:
                        parsing = false;
                        break;
                    default:
                        var value = ParseByToken(token);
                        array.Add(value);
                        break;
                }
            }

            return array;
        }

        private object ParseValue()
        {
            var token = NextToken;
            return ParseByToken(token);
        }

        private object ParseByToken(Token token)
        {
            switch (token)
            {
                case Token.String:
                    return ParseString();
                case Token.Number:
                    return ParseNumber();
                case Token.CurlyOpen:
                    return ParseObject();
                case Token.SquareOpen:
                    return ParseArray();
                case Token.True:
                    return true;
                case Token.False:
                    return false;
                case Token.Null:
                    return null;
                default:
                    return null;
            }
        }

        private string ParseString()
        {
            var builder = new StringBuilder();
            reader.Read();

            var parsing = true;
            while (parsing)
            {
                if (reader.Peek() == -1)
                {
                    break;
                }

                var c = (char)reader.Read();
                switch (c)
                {
                    case '"':
                        parsing = false;
                        break;
                    case '\\':
                        if (reader.Peek() == -1)
                        {
                            parsing = false;
                            break;
                        }

                        c = (char)reader.Read();
                        switch (c)
                        {
                            case '"':
                            case '\\':
                            case '/':
                                builder.Append(c);
                                break;
                            case 'b':
                                builder.Append('\b');
                                break;
                            case 'f':
                                builder.Append('\f');
                                break;
                            case 'n':
                                builder.Append('\n');
                                break;
                            case 'r':
                                builder.Append('\r');
                                break;
                            case 't':
                                builder.Append('\t');
                                break;
                            case 'u':
                                var hex = new char[4];
                                for (var i = 0; i < 4; i++)
                                {
                                    hex[i] = (char)reader.Read();
                                }

                                builder.Append((char)Convert.ToInt32(new string(hex), 16));
                                break;
                        }
                        break;
                    default:
                        builder.Append(c);
                        break;
                }
            }

            return builder.ToString();
        }

        private object ParseNumber()
        {
            var number = NextWord;
            if (number.IndexOf('.') == -1)
            {
                if (long.TryParse(number, NumberStyles.Any, CultureInfo.InvariantCulture, out var parsedInt))
                {
                    return parsedInt;
                }
            }

            if (double.TryParse(number, NumberStyles.Any, CultureInfo.InvariantCulture, out var parsedDouble))
            {
                return parsedDouble;
            }

            return 0;
        }

        private void EatWhitespace()
        {
            while (char.IsWhiteSpace(PeekChar))
            {
                reader.Read();
                if (reader.Peek() == -1)
                {
                    break;
                }
            }
        }

        private char PeekChar => reader.Peek() == -1 ? '\0' : Convert.ToChar(reader.Peek());

        private string NextWord
        {
            get
            {
                var builder = new StringBuilder();
                while (!IsWordBreak(PeekChar))
                {
                    builder.Append((char)reader.Read());
                    if (reader.Peek() == -1)
                    {
                        break;
                    }
                }

                return builder.ToString();
            }
        }

        private Token NextToken
        {
            get
            {
                EatWhitespace();

                if (reader.Peek() == -1)
                {
                    return Token.None;
                }

                switch (PeekChar)
                {
                    case '{':
                        return Token.CurlyOpen;
                    case '}':
                        reader.Read();
                        return Token.CurlyClose;
                    case '[':
                        return Token.SquareOpen;
                    case ']':
                        reader.Read();
                        return Token.SquareClose;
                    case ',':
                        reader.Read();
                        return NextToken;
                    case '"':
                        return Token.String;
                    case ':':
                        return Token.Colon;
                    case '0':
                    case '1':
                    case '2':
                    case '3':
                    case '4':
                    case '5':
                    case '6':
                    case '7':
                    case '8':
                    case '9':
                    case '-':
                        return Token.Number;
                }

                var word = NextWord;
                switch (word)
                {
                    case "false":
                        return Token.False;
                    case "true":
                        return Token.True;
                    case "null":
                        return Token.Null;
                }

                return Token.None;
            }
        }

        private static bool IsWordBreak(char c)
        {
            return char.IsWhiteSpace(c) || WordBreak.IndexOf(c) != -1;
        }

        private enum Token
        {
            None,
            CurlyOpen,
            CurlyClose,
            SquareOpen,
            SquareClose,
            Colon,
            Comma,
            String,
            Number,
            True,
            False,
            Null
        }
    }

    private sealed class Serializer
    {
        private readonly StringBuilder builder;

        private Serializer()
        {
            builder = new StringBuilder();
        }

        public static string Serialize(object obj)
        {
            var instance = new Serializer();
            instance.SerializeValue(obj);
            return instance.builder.ToString();
        }

        private void SerializeValue(object value)
        {
            switch (value)
            {
                case null:
                    builder.Append("null");
                    break;
                case string stringValue:
                    SerializeString(stringValue);
                    break;
                case bool boolValue:
                    builder.Append(boolValue ? "true" : "false");
                    break;
                case IDictionary dictionary:
                    SerializeObject(dictionary);
                    break;
                case IList list:
                    SerializeArray(list);
                    break;
                case char charValue:
                    SerializeString(charValue.ToString());
                    break;
                default:
                    SerializeOther(value);
                    break;
            }
        }

        private void SerializeObject(IDictionary obj)
        {
            var first = true;
            builder.Append('{');

            foreach (var key in obj.Keys)
            {
                if (!first)
                {
                    builder.Append(',');
                }

                SerializeString(key.ToString());
                builder.Append(':');
                SerializeValue(obj[key]);
                first = false;
            }

            builder.Append('}');
        }

        private void SerializeArray(IList array)
        {
            builder.Append('[');
            var first = true;

            foreach (var value in array)
            {
                if (!first)
                {
                    builder.Append(',');
                }

                SerializeValue(value);
                first = false;
            }

            builder.Append(']');
        }

        private void SerializeString(string str)
        {
            builder.Append('\"');

            foreach (var c in str)
            {
                switch (c)
                {
                    case '"':
                        builder.Append("\\\"");
                        break;
                    case '\\':
                        builder.Append("\\\\");
                        break;
                    case '\b':
                        builder.Append("\\b");
                        break;
                    case '\f':
                        builder.Append("\\f");
                        break;
                    case '\n':
                        builder.Append("\\n");
                        break;
                    case '\r':
                        builder.Append("\\r");
                        break;
                    case '\t':
                        builder.Append("\\t");
                        break;
                    default:
                        if (c < 32 || c > 126)
                        {
                            builder.Append("\\u");
                            builder.Append(((int)c).ToString("x4"));
                        }
                        else
                        {
                            builder.Append(c);
                        }
                        break;
                }
            }

            builder.Append('\"');
        }

        private void SerializeOther(object value)
        {
            switch (value)
            {
                case float floatValue:
                    builder.Append(floatValue.ToString("R", CultureInfo.InvariantCulture));
                    break;
                case double doubleValue:
                    builder.Append(doubleValue.ToString("R", CultureInfo.InvariantCulture));
                    break;
                case int intValue:
                    builder.Append(intValue.ToString(CultureInfo.InvariantCulture));
                    break;
                case long longValue:
                    builder.Append(longValue.ToString(CultureInfo.InvariantCulture));
                    break;
                default:
                    builder.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                    break;
            }
        }
    }
}
