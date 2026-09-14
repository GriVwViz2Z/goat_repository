import json
import random

# 读取状态
with open("state.json", "r", encoding="utf-8") as f:
    state = json.load(f)

# 读取记忆
with open("memories.json", "r", encoding="utf-8") as f:
    memories = json.load(f)


# 时间过去一天
state["age"] += 1


# 随机发生一件事
events = [
    "发现了一个新东西",
    "今天有点疲惫",
    "想起了一段过去的记忆",
    "感到非常好奇"
]

event = random.choice(events)


# 根据事件改变状态
if event == "发现了一个新东西":
    curiosity = state["personality"]["curious"]

    state["curiosity"] += 5 * curiosity / 50
    state["mood"] += 3

elif event == "今天有点疲惫":
    sensitivity = state["personality"]["sensitive"]

    state["energy"] -= 10
    state["mood"] -= 3 * sensitivity / 50

elif event == "想起了一段过去的记忆":
    sensitivity = state["personality"]["sensitive"]

    state["mood"] += 2 * sensitivity / 50


elif event == "感到非常好奇":
    curiosity = state["personality"]["curious"]

    state["curiosity"] += 10 * curiosity / 50


# 添加记忆
memories.append(
    f"第{state['age']}天：{event}"
)


# 保存状态
with open("state.json", "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, indent=2)


# 保存记忆
with open("memories.json", "w", encoding="utf-8") as f:
    json.dump(memories, f, ensure_ascii=False, indent=2)


print("今天发生：", event)
print("现在的状态：", state)