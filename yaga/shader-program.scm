
(define-module (yaga shader-program)
  #:use-module (yaga shader-validator)
  #:use-module (yaga environment)
  #:use-module (yaga primitives)
  #:use-module (yaga common)
  #:use-module (srfi srfi-1) ;; find
  #:export (action-shader-program gather-program-vars))


;;
(define (action-shader-program params env)

  ;; Create an object representing the shader program, and perform
  ;; validation on the resulting combination.
  (define (make-program stages)
    
    ;; Validates shader stages, collects the combined inputs and
    ;; transports for later validation.  Returns an a-list of the
    ;; accumulated information.
    (define (accumulate-inputs stages types inputs transports)
      (cond
       [(null? stages)
        (list (cons 'types types)
              (cons 'inputs inputs)
              (cons 'transports transports))]
       [(pair? (car stages))
        (let* ([validation (validate-shader-stage (car stages) env)]
               [shader (cdr validation)]
               [shader-type (car validation)]
               [shader-inputs (fetch 'inputs (cdr shader))]
               [shader-transports (fetch 'transports (cdr shader))]
               [new-types (cons shader-type types)]
               [new-inputs (append shader-inputs inputs)]
               [new-transports (append shader-transports transports)])
          (if (member shader-type types)
              (error "Shader program may only have one shader of each type."))
          (if (not (or (eq? shader-type #:fragment)
                       (null? shader-transports)))
              (error "Only fragment shaders may define 'interpolate' inputs!"))
          (accumulate-inputs (cdr stages) new-types new-inputs new-transports))]
       [else (error "malformed program definition - expected association list")]))

    ;; Build the program object and perform validation.
    (cons (list 'shaders stages) (accumulate-inputs stages '() '() '())))

  (let* ([name (car params)]
         [stages (cdr params)]
         [program (cons name (make-program stages))]
         [types (environment-types env)]
         [shaders (environment-shaders env)]
         [programs (cons program (environment-programs env))])
    (validate-program (cdr program))
    (make-environment types shaders programs)))


;;
(define (gather-program-vars program env)

  ;;
  (define (get-binding name frameset)
    (cond
     [(null? frameset) #f]
     [else     
      (let* ([frame (car frameset)]
             [found (assoc name frame)])
        (or found (get-binding name (cdr frameset))))]))

  ;;
  (define (is-lookup? expr frameset)
    (cond [(null? expr) #f]
          [(pair? expr) (get-binding (car expr) frameset)]
          [else #f]))

  ;;
  (define (traverse expr frameset)
    (cond
     [(or (null? expr)(not (pair? expr))) '()]
     [(pair? expr)
      (let ([found (is-lookup? expr frameset)])
        (cond
         [found (list (cons (cadr found) (cdr expr)))]
         [else
          (let ([recurse (lambda (nexpr) (traverse nexpr frameset))])
            (apply append (map recurse expr)))]))]))
  
  (newline)(newline)
  (let* ([shader-names (map cadr (car (fetch 'shaders program)))]
         [shaders (map (lambda (name) (lookup-shader name env)) shader-names)]
         [inputs (fetch 'inputs program)]
         [transports (fetch 'transports program)]
         [all-vars (append inputs transports)]
         [frameset (cons all-vars '())]
         [inspect (lambda (shader) (traverse (fetch 'body (cdr shader)) frameset))])
    (delete-duplicates (apply append (map inspect shaders)))))