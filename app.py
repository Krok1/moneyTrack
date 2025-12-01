import os
import requests
import json
from datetime import datetime, timedelta
# !!! ІМПОРТУЄМО ДЛЯ РОБОТИ З ЗОБРАЖЕННЯМИ !!!
from PIL import Image 
from io import BytesIO 
# ---------------------------------------------
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai.errors import APIError
from dotenv import load_dotenv

# Завантажуємо змінні з файлу .env (працює тільки локально!)
load_dotenv() 

# --- КОНФІГУРАЦІЯ ---
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
MONO_TOKEN = os.environ.get("MONO_TOKEN")

if GEMINI_API_KEY:
    client = genai.Client(api_key=GEMINI_API_KEY)
else:
    client = None

app = FastAPI(title="Budget Core API")

# Налаштування CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- МОДУЛЬ 1: Банкінг (Monobank) ---
@app.get("/mono-transactions")
async def get_mono_transactions():
    """Отримує виписку за останні 7 днів з Monobank."""
    if not MONO_TOKEN:
        raise HTTPException(status_code=500, detail="MONO_TOKEN не налаштований у змінних середовища.")

    # ... (логіка Monobank залишається без змін) ...
    to_time = int(datetime.now().timestamp())
    from_time = int((datetime.now() - timedelta(days=7)).timestamp())
    account = "0" 
    url = f"https://api.monobank.ua/personal/statement/{account}/{from_time}/{to_time}"
    
    headers = {'X-Token': MONO_TOKEN}
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        txs = response.json()
        clean_txs = []
        for t in txs:
            clean_txs.append({
                "id": t['id'],
                "date": datetime.fromtimestamp(t['time']).strftime('%Y-%m-%d %H:%M'),
                "amount": t['amount'] / 100, 
                "description": t['description'],
                "mcc": t['mcc'] 
            })
        return clean_txs
    else:
        raise HTTPException(status_code=response.status_code, detail=response.text)


# --- МОДУЛЬ 2: Сканер Чеків (ШІ) ---
@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    if not client: 
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY не налаштований.")
    
    if not file.content_type.startswith('image/'):
        raise HTTPException(status_code=400, detail="Потрібне зображення.")

    # 1. Читання та підготовка зображення
    try:
        # Читаємо байти файлу, надісланого Flutter
        image_data = await file.read()
        
        # Створюємо об'єкт PIL Image з байтів
        image = Image.open(BytesIO(image_data))
        
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Помилка читання або відкриття зображення: {e}")


    # 2. Виклик Gemini API
    try:
        prompt = """
        Ти фінансовий асистент. Проаналізуй це фото чека.
        Витягни дані у форматі чистого JSON (без markdown і пояснень):
        {
            "store": "назва магазину",
            "date": "дата у форматі YYYY-MM-DD або DD-MM-YYYY",
            "total_amount": сума числом,
            "currency": "UAH" або "PLN" тощо,
            "items": [
                {"name": "назва товару", "price": ціна товару, "category": "категорія (Їжа, Побут, Техніка)"}
            ]
        }
        Якщо чогось не видно, постав null.
        """
        
        # Передаємо prompt та об'єкт Image напряму
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=[image, prompt] # image йде першим
        )

        # 3. Очищення та повернення JSON
        clean_json = response.text.replace('```json', '').replace('```', '').strip()
        data = json.loads(clean_json)
        return data
    
    except APIError as e:
        raise HTTPException(status_code=500, detail=f"Помилка Gemini API: {e}")
    except json.JSONDecodeError as e:
        # Якщо ШІ повернув не валідний JSON
        raise HTTPException(status_code=500, detail=f"ШІ повернув невірний JSON. Помилка парсингу: {e}. Відповідь ШІ: {response.text[:200]}...")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Невідома помилка: {e}")

# Маршрут для перевірки (health check)
@app.get("/")
def read_root():
    return {"status": "ok", "message": "Budget Core API працює!"}