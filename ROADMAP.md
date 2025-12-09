# Project Roadmap
---
## Phase 1 `AI Core - Basic`
 - [x] **Release** `1.0.0`
    - Text-only interface for the AI Core API (Gemini Nano / Flan T-5) implementation, Play Store and source release
 - [x] **UI and UX** `1.0.1`
    - Multi-chat application with finalized MD3 style and state control for model download
 - [x] **Basic features** `1.1.0`
    - Multichat, chat pinning, basic per-chat settings
 - [x] **Hotfixes and monitoring** `1.1.1`, `1.1.2`
    - Optional analytics and crash reporting, logging, issue fixes in UI and backend
 - [ ] **Additional features**
    - Per-chat personas, temperature and token limit settings, etc. 
 - [ ] **Generation extension**
    - Workaround for 25s response generation time that ends answers prematurely
 - [ ] **Master Prompt fixes**
    - Finalizing the master prompt so it delivers more consistency
 - [ ] **Monetization**
    - Monetize the project to allocate more time to the project
 - [ ] **Finalization**
    - Polishing and fixing issues, supporting users and optimisations


## Phase 2 `AI Core - Improved`
 - [ ] **Agentism**
    - Add agentic and RAG capabilities to the model with tool use loops, tool usage protocol
 - [ ] **Context expansion**
    - Find a way to allow model to use more data simultaneously, without overflowing the context window
 - [ ] **Multimodality**
    - Add image recognition that is supported by Gemini Nano
- [ ] **Ephemeral Context**
    - Implementing a "Short-Term Memory" buffer for heavy data (files/logs) that doesn't pollute the long-term chat history.

## Phase 3 `Model-agnosticizm`
 - [ ] **Custom models**
    - Allow users to set up and run custom models (like Gemma 2B) besides Gemini Nano for redundancy
 - [ ] **Connectivity**
    - Create a companion app that allows bigger models to run in other environment to connect the *PAIOS* to better hardware (prolly via Ollama)
    - This has to be made in a way that allows even users who are not tech-savvy to just install the model and run it
 - [ ] **Failover**
    - Auto-switch to local model if the remote connection drops.

## Phase 4 `PAIOS`
 - [ ] **File System Access**
    - Read access to files on the device, in the network or online for more capabilities
 - [ ] **Scripting**
    - Allow the AI to use scripts to interact with other devices and use better tools like smart home integration
 - [ ] **Extenstions "market"**
    - Create a way for users to create extensions and publish them for other users to use
 - [ ] **Voice chat**
    - Real-time, low-latency voice interaction (running locally). Possibly, ability to join chats on social media apps or act on behalf of user
 - [ ] **And much, much more**
