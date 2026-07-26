"""Small, transparent genre classifier for public video metadata.

It uses only titles/descriptions/tags returned by the provider; it never tries to
infer protected content or inspect video frames.
"""

GENRE_WORDS = {
    "Хоррор": ("horror", "ужас", "хоррор", "страш", "слэшер"),
    "Комедия": ("comedy", "комед", "смешн", "юмор"),
    "Драма": ("drama", "драма", "драмат"),
    "Романтика": ("romance", "romantic", "мелодрам", "романтик", "любов"),
    "Триллер": ("thriller", "триллер", "напряж"),
    "Боевик": ("action", "боевик", "экшен", "action movie"),
    "Фантастика": ("sci-fi", "science fiction", "фантаст", "космос"),
    "Детектив": ("detective", "crime", "детектив", "криминал"),
    "Анимация": ("animation", "anime", "мульт", "анимац"),
    "Документальный": ("documentary", "документал"),
}


def detect_genres(*values):
    text = " ".join(str(value or "") for value in values).lower()
    result = [genre for genre, words in GENRE_WORDS.items() if any(word in text for word in words)]
    return result or ["Другое"]
