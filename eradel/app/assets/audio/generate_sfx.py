import math
import struct
import random
import wave
import os

sample_rate = 44100

def create_hit_normal(filepath):
    # 일반 타격음: 0.18초 펀치 + 스윙/슬래시 임팩트
    duration = 0.20
    num_samples = int(sample_rate * duration)
    samples = []
    
    for i in range(num_samples):
        t = i / sample_rate
        # Envelope: 빠른 어택(0.005s), 지수 감쇠 decay
        if t < 0.005:
            env = t / 0.005
        else:
            env = math.exp(-(t - 0.005) * 22.0)
            
        # 1. 펀치 바디: 주파수가 180Hz에서 55Hz로 급격히 떨어지는 피치 드롭
        freq = 60.0 + 140.0 * math.exp(-t * 35.0)
        body = math.sin(2.0 * math.pi * freq * t)
        
        # 2. 노이즈 슬래시 임팩트 (어택 초반에 집중)
        noise_env = math.exp(-t * 50.0)
        noise = (random.random() * 2.0 - 1.0) * noise_env
        
        # 3. 중음역대 펀치 (110Hz 고조파)
        mid = 0.4 * math.sin(2.0 * math.pi * 110.0 * t) * math.exp(-t * 28.0)
        
        # 믹싱
        sample = (body * 0.65 + noise * 0.45 + mid * 0.3) * env
        # 소프트 클리핑
        sample = max(-0.95, min(0.95, sample * 1.2))
        
        # 16-bit PCM 정규화
        val = int(sample * 32767.0)
        samples.append(val)
        
    with wave.open(filepath, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        data = struct.pack('<' + 'h' * len(samples), *samples)
        wf.writeframes(data)
    print(f"Created {filepath} ({len(samples)} samples)")

def create_hit_crit(filepath):
    # 크리티컬 타격음: 0.35초 메탈릭 참격 + 헤비 서브베이스 임팩트
    duration = 0.35
    num_samples = int(sample_rate * duration)
    samples = []
    
    for i in range(num_samples):
        t = i / sample_rate
        if t < 0.003:
            env = t / 0.003
        else:
            env = math.exp(-(t - 0.003) * 12.0)
            
        # 1. 헤비 베이스 서브 럼블 (200Hz -> 45Hz)
        freq_sub = 45.0 + 180.0 * math.exp(-t * 25.0)
        sub = math.sin(2.0 * math.pi * freq_sub * t)
        
        # 2. 날카로운 메탈릭 참격 / 파열음 (1250Hz, 1950Hz, 3100Hz 공명)
        metal_env = math.exp(-t * 18.0)
        metal = (
            0.5 * math.sin(2.0 * math.pi * 1250.0 * t) +
            0.35 * math.sin(2.0 * math.pi * 1950.0 * t) +
            0.2 * math.sin(2.0 * math.pi * 3100.0 * t)
        ) * metal_env
        
        # 3. 강렬한 크런치 노이즈 파열
        noise_env = math.exp(-t * 40.0)
        noise = (random.random() * 2.0 - 1.0) * noise_env
        
        # 믹싱
        sample = (sub * 0.6 + metal * 0.5 + noise * 0.45) * env
        # 새츄레이션
        sample = math.tanh(sample * 1.5) * 0.95
        
        val = int(sample * 32767.0)
        samples.append(val)
        
    with wave.open(filepath, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        data = struct.pack('<' + 'h' * len(samples), *samples)
        wf.writeframes(data)
    print(f"Created {filepath} ({len(samples)} samples)")

if __name__ == '__main__':
    out_dir = r"c:\Users\user\Documents\projects\Google-Jules-Temp-Repo\Godot\eradel\assets\audio"
    os.makedirs(out_dir, exist_ok=True)
    create_hit_normal(os.path.join(out_dir, "hit_normal.wav"))
    create_hit_crit(os.path.join(out_dir, "hit_crit.wav"))

