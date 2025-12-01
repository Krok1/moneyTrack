import os
import requests
import json
import google.generativeai as genai
from datetime import datetime

# --- КОНФІГУРАЦІЯ (Встав сюди свої ключі) ---
GEMINI_API_KEY = "-s3TK8l12414124"
MONO_TOKEN = "-U123124PC38"

# Налаштування AI
genai.configure(api_key=GEMINI_API_KEY)

# --- МОДУЛЬ 1: Сканер Чеків (ШІ) ---
def scan_receipt_with_ai(image_path):
    """
    Відправляє фото чека в Gemini і отримує JSON з покупками.
    Безкоштовно в рамках лімітів Google AI Studio.
    """
    print(f"🤖 Аналізую чек: {image_path}...")
    
    model = genai.GenerativeModel('gemini-1.5-flash') # Швидка і дешева (часто безкоштовна) модель
    
    # Завантажуємо зображення
    sample_file = genai.upload_file(path=image_path, display_name="Receipt")
    
    prompt = """
    Ти фінансовий асистент. Проаналізуй це фото чека.
    Витягни дані у форматі чистого JSON (без markdown):
    {
        "store": "назва магазину",
        "date": "дата у форматі YYYY-MM-DD",
        "total_amount": сума числом,
        "currency": "UAH" або "PLN" тощо,
        "items": [
            {"name": "назва товару", "price": ціна товару, "category": "категорія (Їжа, Побут, Техніка)"}
        ]
    }
    Якщо чогось не видно, постав null.
    """
    
    response = model.generate_content([sample_file, prompt])
    
    # Чистимо відповідь від зайвих символів, якщо ШІ їх додав
    clean_json = response.text.replace('```json', '').replace('```', '').strip()
    
    try:
        data = json.loads(clean_json)
        return data
    except json.JSONDecodeError:
        return {"error": "Не вдалося розпізнати JSON", "raw": response.text}

# --- МОДУЛЬ 2: Банкінг (Monobank Приклад) ---
def get_mono_transactions():
    """Отримує виписку за останні 31 день"""
    print("🏦 Отримую дані з Monobank...")
    
    # Unix час: зараз і місяць тому
    to_time = int(datetime.now().timestamp())
    from_time = to_time - (31 * 24 * 60 * 60)
    
    # 0 - це зазвичай чорна картка (рахунок за замовчуванням)
    account = "0" 
    url = f"https://api.monobank.ua/personal/statement/{account}/{from_time}/{to_time}"
    
    headers = {'X-Token': MONO_TOKEN}
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        txs = response.json()
        clean_txs = []
        for t in txs:
            clean_txs.append({
                "date": datetime.fromtimestamp(t['time']).strftime('%Y-%m-%d %H:%M'),
                "amount": t['amount'] / 100, # В копійках, ділимо на 100
                "description": t['description'],
                "mcc": t['mcc'] # Код категорії
            })
        return clean_txs
    else:
        return {"error": f"Помилка банку: {response.status_code}"}

# --- ТЕСТОВИЙ ЗАПУСК ---
if __name__ == "__main__":
    # 1. Тест Монобанку
    # transactions = get_mono_transactions()
    # print(json.dumps(transactions, indent=2, ensure_ascii=False))

    # 2. Тест Чека (Поклади фото чека поруч і назви receipt.jpg)
    if os.path.exists("receipt.jpg"):
        receipt_data = scan_receipt_with_ai("receipt.jpg")
        print(json.dumps(receipt_data, indent=2, ensure_ascii=False))
    else:
        print("⚠️ Файл receipt.jpg не знайдено. Зроби фото чека і поклади в папку.")
