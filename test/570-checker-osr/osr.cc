/*
 * Copyright (C) 2016 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "art_method.h"
#include "jit/jit.h"
#include "jit/jit_code_cache.h"
#include "jit/profiling_info.h"
#include "oat_quick_method_header.h"
#include "scoped_thread_state_change.h"
#include "stack_map.h"

namespace art {

class OsrVisitor : public StackVisitor {
 public:
  explicit OsrVisitor(Thread* thread)
      SHARED_REQUIRES(Locks::mutator_lock_)
      : StackVisitor(thread, nullptr, StackVisitor::StackWalkKind::kIncludeInlinedFrames),
        in_osr_method_(false),
        in_interpreter_(false) {}

  bool VisitFrame() SHARED_REQUIRES(Locks::mutator_lock_) {
    ArtMethod* m = GetMethod();
    std::string m_name(m->GetName());

    if ((m_name.compare("$noinline$returnInt") == 0) ||
        (m_name.compare("$noinline$returnFloat") == 0) ||
        (m_name.compare("$noinline$returnDouble") == 0) ||
        (m_name.compare("$noinline$returnLong") == 0) ||
        (m_name.compare("$noinline$deopt") == 0) ||
        (m_name.compare("$noinline$inlineCache") == 0) ||
        (m_name.compare("$noinline$stackOverflow") == 0)) {
      const OatQuickMethodHeader* header =
          Runtime::Current()->GetJit()->GetCodeCache()->LookupOsrMethodHeader(m);
      if (header != nullptr && header == GetCurrentOatQuickMethodHeader()) {
        in_osr_method_ = true;
      } else if (IsCurrentFrameInInterpreter()) {
        in_interpreter_ = true;
      }
      return false;
    }
    return true;
  }

  bool in_osr_method_;
  bool in_interpreter_;
};

extern "C" JNIEXPORT jboolean JNICALL Java_Main_ensureInOsrCode(JNIEnv*, jclass) {
  jit::Jit* jit = Runtime::Current()->GetJit();
  if (jit == nullptr) {
    // Just return true for non-jit configurations to stop the infinite loop.
    return JNI_TRUE;
  }
  ScopedObjectAccess soa(Thread::Current());
  OsrVisitor visitor(soa.Self());
  visitor.WalkStack();
  return visitor.in_osr_method_;
}

extern "C" JNIEXPORT jboolean JNICALL Java_Main_ensureInInterpreter(JNIEnv*, jclass) {
  if (!Runtime::Current()->UseJit()) {
    // The return value is irrelevant if we're not using JIT.
    return false;
  }
  ScopedObjectAccess soa(Thread::Current());
  OsrVisitor visitor(soa.Self());
  visitor.WalkStack();
  return visitor.in_interpreter_;
}

class ProfilingInfoVisitor : public StackVisitor {
 public:
  explicit ProfilingInfoVisitor(Thread* thread)
      SHARED_REQUIRES(Locks::mutator_lock_)
      : StackVisitor(thread, nullptr, StackVisitor::StackWalkKind::kIncludeInlinedFrames) {}

  bool VisitFrame() SHARED_REQUIRES(Locks::mutator_lock_) {
    ArtMethod* m = GetMethod();
    std::string m_name(m->GetName());

    if ((m_name.compare("$noinline$inlineCache") == 0) ||
        (m_name.compare("$noinline$stackOverflow") == 0)) {
      ProfilingInfo::Create(Thread::Current(), m, /* retry_allocation */ true);
      return false;
    }
    return true;
  }
};

extern "C" JNIEXPORT void JNICALL Java_Main_ensureHasProfilingInfo(JNIEnv*, jclass) {
  if (!Runtime::Current()->UseJit()) {
    return;
  }
  ScopedObjectAccess soa(Thread::Current());
  ProfilingInfoVisitor visitor(soa.Self());
  visitor.WalkStack();
}

class OsrCheckVisitor : public StackVisitor {
 public:
  explicit OsrCheckVisitor(Thread* thread)
      SHARED_REQUIRES(Locks::mutator_lock_)
      : StackVisitor(thread, nullptr, StackVisitor::StackWalkKind::kIncludeInlinedFrames) {}

  bool VisitFrame() SHARED_REQUIRES(Locks::mutator_lock_) {
    ArtMethod* m = GetMethod();
    std::string m_name(m->GetName());

    jit::Jit* jit = Runtime::Current()->GetJit();
    if ((m_name.compare("$noinline$inlineCache") == 0) ||
        (m_name.compare("$noinline$stackOverflow") == 0)) {
      while (jit->GetCodeCache()->LookupOsrMethodHeader(m) == nullptr) {
        // Sleep to yield to the compiler thread.
        sleep(0);
        // Will either ensure it's compiled or do the compilation itself.
        jit->CompileMethod(m, Thread::Current(), /* osr */ true);
      }
      return false;
    }
    return true;
  }
};

extern "C" JNIEXPORT void JNICALL Java_Main_ensureHasOsrCode(JNIEnv*, jclass) {
  if (!Runtime::Current()->UseJit()) {
    return;
  }
  ScopedObjectAccess soa(Thread::Current());
  OsrCheckVisitor visitor(soa.Self());
  visitor.WalkStack();
}

}  // namespace art
