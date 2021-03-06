(in-package #:vivace-graph)

(defun add-triple (subject predicate object &optional graph)
  (let ((*graph* (or graph *graph*)))
    (let ((subject (or (lookup-node subject *graph*) 
		       (make-new-node :value subject)))
	  (predicate (or (lookup-predicate predicate *graph*) 
			 (make-new-predicate :name predicate)))
	  (object (or (lookup-node object *graph*) 
		      (make-new-node :value object))))
      (make-new-triple *graph* subject predicate object))))

;(defun get-triples-list (&key limit graph)
;  (let ((*graph* (or graph *graph*)))
;    (let ((result nil) (count 0))
;      (map-skip-list-values #'(lambda (triple) (push triple result)) (triples *graph*))
;      (nreverse result))))

(defun get-triples (&key s p o g)
  (let ((*graph* (or g *graph*)))
    (cond ((and s p o)
	   (lookup-triple s p o :g *graph*))
	  ((and s p)
	   (get-subjects-predicates s p *graph*))
	  ((and s o)
	   (get-subjects-objects s o *graph*))
	  ((and p o)
	   (get-predicates-objects p o *graph*))
	  (s
	   (get-subjects s *graph*))
	  (p
	   (get-predicates p *graph*))
	  (o
	   (get-objects o *graph*))
	  (t nil))))

;(defun triple-count (&optional graph)
;  (skip-list-length (triples (or graph *graph*))))

(defun load-graph! (file)
  (let ((config (py-configparser:make-config)))
    (py-configparser:read-files config (list file))
    (let ((uuid (uuid:make-uuid-from-string (py-configparser:get-option config "default" "uuid"))))
      (sb-ext:with-locked-hash-table (*graph-table*)
	(let ((graph (gethash uuid *graph-table*)))
	  (if (and (graph? graph) (not (shutdown? graph)))
	      (setq *graph* graph)
	      (let ((graph (make-graph :graph-uuid uuid
				       :graph-name (py-configparser:get-option 
						    config "default" "name")
				       :graph-location (py-configparser:get-option 
							config "default" "location"))))
		(setf (triple-db graph) (open-store 
					 (format nil "~A/triples.kct" (graph-location graph)))
		      (rule-db graph) (open-hash (format nil "~A/rules.kch" (graph-location graph)))
		      (functor-db graph) (open-hash 
					  (format nil "~A/functors.kch" (graph-location graph)))
		      (full-text-idx graph)
		      (make-instance 'montezuma:index 
				     :default-field "*"
				     :fields '("subject" "object")
				     :min-merge-docs 5000 
				     :path (format nil "~A/full-text-idx" (graph-location graph)))
		      (gethash (graph-uuid graph) *graph-table*) graph
		      *graph* graph))))))
    (load-all-functors *graph*)
    (load-all-rules *graph*)
    *graph*))

(defun make-new-graph (&key name location)
  (let ((graph (make-graph))
	(config-file (format nil "~A/config.ini" location)))
    (with-open-file (stream config-file
			    :direction :output
			    :if-does-not-exist :create
			    :if-exists :error)
      (format stream "[default]~%")
      (format stream "uuid=~A~%" (print-object (graph-uuid graph) nil))
      (format stream "name=~A~%" name)
      (format stream "location=~A~%" location))
    (load-graph! config-file)))

(defmethod shutdown-graph ((graph graph) &key waitp)
  (declare (ignore waitp))
  (sb-ext:with-locked-hash-table (*graph-table*)
    (setf (shutdown? graph) t)
    (when (eql *graph* graph) (setq *graph* nil))
    (close-hash (functor-db graph))
    (close-hash (rule-db graph))
    (close-store (triple-db graph))
    (remhash (graph-uuid graph) *graph-table*)))
