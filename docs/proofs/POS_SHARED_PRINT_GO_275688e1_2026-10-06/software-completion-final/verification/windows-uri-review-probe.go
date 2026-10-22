package main
import("fmt";"net/url")
func main(){u:=url.URL{Scheme:"file",Path:"C:/fixture/edge.db",RawQuery:"mode=ro"};fmt.Println(u.String());p,e:=url.Parse(u.String());fmt.Printf("host=%q path=%q error=%v\n",p.Host,p.Path,e)}
