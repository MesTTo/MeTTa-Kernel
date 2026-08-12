;Purpose: the lib_torch extension library from plain MeTTa: tensors, algebra
;  and autograd through py-call with no Python-side setup. Skipped by test.sh
;  alongside torch.metta, since CI has no PyTorch; run it directly with
;  sh run.sh ./examples/torch_lib.metta
;Open Obligations:
;  To Do: None
;  Hacks: None
;  Future Enhancements: None

!(import! &self (library lib_torch))

!(test (torch-tolist (torch-matmul (torch-tensor ((1.0 2.0 3.0) (4.0 5.0 6.0)))
                                   (torch-tensor ((7.0 8.0) (9.0 10.0) (11.0 12.0)))))
       ((58.0 64.0) (139.0 154.0)))

!(test (torch-item (torch-sum (torch-tensor (1.0 2.0 3.0))))
       6.0)

!(test (torch-shape (torch-tensor ((1.0 2.0) (3.0 4.0) (5.0 6.0))))
       (3 2))

;Autograd end to end: d/dw sum(w * x) = x
!(test (let* (($w (torch-requires-grad (torch-tensor (2.0 3.0))))
              ($x (torch-tensor (5.0 7.0)))
              ($loss (torch-sum (torch-mul $w $x)))
              ($b (torch-backward $loss)))
             (torch-tolist (torch-grad $w)))
       (5.0 7.0))
