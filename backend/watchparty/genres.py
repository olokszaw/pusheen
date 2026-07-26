"""Genre detection from public page metadata only.

The resolver receives title, description, categories and tags from the video
provider.  This map deliberately stays transparent: it never guesses from the
actual video, bypasses a service, or accesses protected content.
"""

GENRE_WORDS = {
    "Хоррор": ("horror", "ужас", "хоррор", "страш", "слэшер", "zombie", "зомби"),
    "Комедия": ("comedy", "комед", "смешн", "юмор", "парод"),
    "Драма": ("drama", "драма", "драмат"),
    "Романтика": ("romance", "romantic", "мелодрам", "романтик", "любов"),
    "Триллер": ("thriller", "триллер", "напряж"),
    "Боевик": ("action", "боевик", "экшен", "action movie"),
    "Приключения": ("adventure", "приключ", "quest"),
    "Фантастика": ("sci-fi", "science fiction", "фантаст", "космос", "space opera"),
    "Фэнтези": ("fantasy", "фэнтези", "магия", "волшеб"),
    "Детектив": ("detective", "детектив", "mystery", "тайна"),
    "Криминал": ("crime", "криминал", "gangster", "мафия", "ограблен"),
    "Анимация": ("animation", "anime", "мульт", "анимац", "cartoon"),
    "Семейный": ("family", "семейн", "детск"),
    "Документальный": ("documentary", "документал", "документ"),
    "Военный": ("war", "военн", "world war"),
    "Исторический": ("history", "historical", "историч", "биограф"),
    "Музыка": ("music", "musical", "музык", "концерт"),
    "Спорт": ("sport", "sports", "спорт", "футбол", "хоккей"),
    "Вестерн": ("western", "вестерн"),
    "Реалити": ("reality", "реалити", "шоу"),
    "Новости": ("news", "новост"),
    "Короткометражка": ("short film", "короткометраж", "short movie"),
}


def detect_genres(*values):
    text = " ".join(str(value or "") for value in values).lower()
    result = [genre for genre, words in GENRE_WORDS.items() if any(word in text for word in words)]
    return result or ["Другое"]
